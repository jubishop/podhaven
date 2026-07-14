// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// MARK: - Container

extension Container {
  var transcriptionQueue: Factory<TranscriptionQueue> {
    Factory(self) { TranscriptionQueue() }.scope(.cached)
  }
}

// MARK: - TranscriptionStatus

enum TranscriptionStatus: Hashable, Sendable {
  case none
  case queued
  case transcribing(Double)
  case transcribed
  case failed

  var canTranscribe: Bool {
    switch self {
    case .none, .failed: return true
    case .queued, .transcribing, .transcribed: return false
    }
  }
}

// MARK: - TranscriptionWorkStream

private final class TranscriptionWorkStream: Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<Episode.ID>.Continuation?
    var episodeID: Episode.ID?
  }

  private let state = ThreadSafe(State())

  func start(with episodeID: Episode.ID?) -> AsyncStream<Episode.ID> {
    let (stream, continuation) = AsyncStream.makeStream(
      of: Episode.ID.self,
      bufferingPolicy: .bufferingNewest(1)
    )
    state { state in
      state.continuation?.finish()
      state.continuation = continuation
      state.episodeID = episodeID
      if let episodeID {
        continuation.yield(episodeID)
      }
    }
    return stream
  }

  func update(to episodeID: Episode.ID?) {
    state { state in
      guard state.episodeID != episodeID else { return }
      state.episodeID = episodeID
      if let episodeID {
        state.continuation?.yield(episodeID)
      }
    }
  }

  func finish() {
    state { state in
      state.continuation?.finish()
      state.continuation = nil
      state.episodeID = nil
    }
  }
}

// MARK: - TranscriptionQueue

struct TranscriptionQueue: Sendable {
  private static let log = Log.as(LogSubsystem.Transcription.queue)

  private let consumerLock = ThreadLock()
  private let mutationLock = ThreadSafe(())
  private let workStream = TranscriptionWorkStream()

  // Persisted ordered work-list in UserDefaults (not SQLite): survives
  // termination so TranscriptionProcessor can resume the head on next launch.
  @PersistedBroadcast("transcriptionQueue") var episodeIDs: [Episode.ID] = []

  // The in-flight episode's progress (0...1). At most one entry, mirroring
  // SharedState.downloadProgress.
  @Broadcasted var progress: [Episode.ID: Double] = [:]

  // Episodes whose last attempt failed, surfaced until retried or dismissed.
  @Broadcasted var failed: Set<Episode.ID> = []

  fileprivate init() {}

  // Keeps exclusive stream ownership and cleanup inside the queue so callers
  // cannot finish another consumer's subscription.
  func withWorkStream(
    _ operation: @Sendable (AsyncStream<Episode.ID>) async throws -> Void
  ) async throws {
    await consumerLock.waitForClaim()
    defer { consumerLock.release() }
    try Task.checkCancellation()

    let stream = mutationLock { _ in
      workStream.start(with: episodeIDs.first)
    }
    defer {
      mutationLock { _ in
        workStream.finish()
      }
    }

    try await operation(stream)
  }

  // MARK: - Mutations

  func enqueue(_ episodeID: Episode.ID) {
    let depth = mutationLock { _ in
      let previousHead = episodeIDs.first
      $failed.update { _ = $0.remove(episodeID) }
      $episodeIDs.update { ids in
        guard !ids.contains(episodeID) else { return }
        ids.append(episodeID)
      }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
      return episodeIDs.count
    }
    Self.log.debug("enqueued \(episodeID); depth \(depth)")
  }

  func remove(_ episodeID: Episode.ID) {
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
  }

  // MARK: - Progress

  func setProgress(_ value: Double, for episodeID: Episode.ID) {
    Assert.precondition(
      value >= 0 && value <= 1,
      "progress must be between 0 and 1 but is \(value)"
    )
    $progress.update { $0[episodeID] = value }
  }

  func clearProgress(for episodeID: Episode.ID) {
    $progress.update { _ = $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Failure

  func fail(_ episodeID: Episode.ID) {
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      $failed.update { _ = $0.insert(episodeID) }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
  }

  func clearFailed(_ episodeID: Episode.ID) {
    $failed.update { _ = $0.remove(episodeID) }
  }

  // MARK: - Status

  func status(for episodeID: Episode.ID, hasTranscript: Bool) -> TranscriptionStatus {
    if hasTranscript { return .transcribed }
    if let value = progress[episodeID] { return .transcribing(value) }
    if episodeIDs.contains(episodeID) { return .queued }
    if failed.contains(episodeID) { return .failed }
    return .none
  }
}
