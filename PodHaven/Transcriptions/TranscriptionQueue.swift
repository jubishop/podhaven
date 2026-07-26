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
  case queued(position: Int, total: Int)
  case transcribing(Double)
  case cancelling
  case transcribed
  case failed

  var canTranscribe: Bool {
    switch self {
    case .none, .failed: return true
    case .queued, .transcribing, .cancelling, .transcribed: return false
    }
  }

  var canCancel: Bool {
    switch self {
    case .queued, .transcribing: return true
    case .none, .cancelling, .transcribed, .failed: return false
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

  private let consumerLock: ThreadLock
  private let persistenceLock: ThreadLock
  private let mutationLock: ThreadSafe<Void>
  private let store: TranscriptionQueueStore
  private let workStream: TranscriptionWorkStream
  private let initialLoad: Task<Void, Never>

  // Durable ordered work survives termination so TranscriptionProcessor can
  // resume the head on next launch.
  @Broadcasted var episodeIDs: [Episode.ID]

  // The in-flight episode's progress (0...1). At most one entry, mirroring
  // SharedState.downloadProgress.
  @Broadcasted var progress: [Episode.ID: Double] = [:]

  // Active user cancellations remain visible while cooperative cleanup runs.
  @Broadcasted var cancelling: Set<Episode.ID> = []

  // Episodes whose last attempt failed, surfaced until retried or dismissed.
  @Broadcasted var failed: Set<Episode.ID> = []

  fileprivate init() {
    let store = Container.shared.transcriptionQueueStore()
    let consumerLock = ThreadLock()
    let persistenceLock = ThreadLock()
    let mutationLock = ThreadSafe(())
    let workStream = TranscriptionWorkStream()
    let episodeIDs = Broadcasted(wrappedValue: [Episode.ID]())

    self.store = store
    self.consumerLock = consumerLock
    self.persistenceLock = persistenceLock
    self.mutationLock = mutationLock
    self.workStream = workStream
    _episodeIDs = episodeIDs
    initialLoad = Task {
      do {
        let persistedEpisodeIDs = try await store.fetchAll()
        mutationLock { _ in
          episodeIDs.projectedValue.new(persistedEpisodeIDs)
          workStream.update(to: persistedEpisodeIDs.first)
        }
      } catch {
        Assert.fatal(
          "Failed to load transcription queue: \(ErrorKit.message(for: error))"
        )
      }
    }
  }

  func waitUntilLoaded() async {
    await initialLoad.value
  }

  // Keeps exclusive stream ownership and cleanup inside the queue so callers
  // cannot finish another consumer's subscription.
  func withWorkStream(
    _ operation: @Sendable (AsyncStream<Episode.ID>) async throws -> Void
  ) async throws {
    await waitUntilLoaded()
    try await consumerLock.waitForClaim()
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

  func enqueue(_ episodeID: Episode.ID) async throws {
    try await enqueue([episodeID])
  }

  func enqueue(_ episodeIDs: [Episode.ID]) async throws {
    guard !episodeIDs.isEmpty else { return }
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let persistedEpisodeIDs = try await store.enqueue(episodeIDs)
    let depth = mutationLock { _ in
      let previousHead = self.episodeIDs.first
      $cancelling.update { $0.subtract(episodeIDs) }
      $failed.update { $0.subtract(episodeIDs) }
      $episodeIDs.new(persistedEpisodeIDs)
      if self.episodeIDs.first != previousHead {
        workStream.update(to: self.episodeIDs.first)
      }
      return self.episodeIDs.count
    }
    Self.log.debug("enqueued \(episodeIDs.count) episodes; depth \(depth)")
  }

  func remove(_ episodeID: Episode.ID) async throws {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let persistedEpisodeIDs = try await store.remove(episodeID)
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.new(persistedEpisodeIDs)
      $progress.update { $0.removeValue(forKey: episodeID) }
      $cancelling.update { $0.remove(episodeID) }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
  }

  func beginCancellation(of episodeID: Episode.ID) async throws -> Bool {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let isQueued = mutationLock { _ in
      guard episodeIDs.contains(episodeID) else { return false }
      $cancelling.update { $0.insert(episodeID) }
      return true
    }
    guard isQueued else { return false }

    let persistedEpisodeIDs: [Episode.ID]
    do {
      persistedEpisodeIDs = try await store.remove(episodeID)
    } catch {
      mutationLock { _ in
        $cancelling.update { $0.remove(episodeID) }
      }
      throw error
    }

    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.new(persistedEpisodeIDs)
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
    return true
  }

  func finishCancellation(of episodeID: Episode.ID) {
    mutationLock { _ in
      $progress.update { $0.removeValue(forKey: episodeID) }
      $cancelling.update { $0.remove(episodeID) }
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
    $progress.update { $0.removeValue(forKey: episodeID) }
  }

  // MARK: - Failure

  func fail(_ episodeID: Episode.ID) async throws {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let persistedEpisodeIDs = try await store.remove(episodeID)
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.new(persistedEpisodeIDs)
      $progress.update { $0.removeValue(forKey: episodeID) }
      $cancelling.update { $0.remove(episodeID) }
      $failed.update { $0.insert(episodeID) }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
  }

  func clearFailed(_ episodeID: Episode.ID) {
    $failed.update { $0.remove(episodeID) }
  }

  // MARK: - Status

  func status(for episodeID: Episode.ID, hasTranscript: Bool) -> TranscriptionStatus {
    if hasTranscript { return .transcribed }
    if cancelling.contains(episodeID) { return .cancelling }
    if let value = progress[episodeID] { return .transcribing(value) }
    let queuedEpisodeIDs = episodeIDs
    if let index = queuedEpisodeIDs.firstIndex(of: episodeID) {
      return .queued(position: index + 1, total: queuedEpisodeIDs.count)
    }
    if failed.contains(episodeID) { return .failed }
    return .none
  }
}
