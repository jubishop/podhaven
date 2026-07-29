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
  case paused(Double)
  case pausing
  case discarding
  case transcribed
  case failed

  var canTranscribe: Bool {
    switch self {
    case .none, .paused, .failed: return true
    case .queued, .transcribing, .pausing, .discarding, .transcribed: return false
    }
  }

  var canPause: Bool {
    switch self {
    case .queued, .transcribing: return true
    case .none, .paused, .pausing, .discarding, .transcribed, .failed: return false
    }
  }
}

enum TranscriptionInterruption: Hashable, Sendable {
  case pausing
  case discarding
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
  private let store: any TranscriptionQueueStoring
  private let workStream: TranscriptionWorkStream
  private let initialLoad: Task<Void, Never>

  @Broadcasted var episodeIDs: [Episode.ID]
  @Broadcasted var progress: [Episode.ID: Double] = [:]
  @Broadcasted var interruptions: [Episode.ID: TranscriptionInterruption] = [:]
  @Broadcasted var failed: Set<Episode.ID> = []

  fileprivate init() {
    let consumerLock = ThreadLock()
    let persistenceLock = ThreadLock()
    let mutationLock = ThreadSafe(())
    let store = Container.shared.transcriptionQueueStore()
    let workStream = TranscriptionWorkStream()
    let episodeIDs = Broadcasted(wrappedValue: [Episode.ID]())

    self.consumerLock = consumerLock
    self.persistenceLock = persistenceLock
    self.mutationLock = mutationLock
    self.store = store
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

    let maximumCount =
      Container.shared.userSettings().boundedMaxTranscriptionQueueLength
    let insertedEpisodeIDs = try await store.enqueue(
      episodeIDs,
      maximumCount: maximumCount
    )
    guard !insertedEpisodeIDs.isEmpty else { return }

    let depth = mutationLock { _ in
      let previousHead = self.episodeIDs.first
      $interruptions.update { interruptions in
        for episodeID in insertedEpisodeIDs {
          interruptions.removeValue(forKey: episodeID)
        }
      }
      $failed.update { $0.subtract(insertedEpisodeIDs) }
      $episodeIDs.update { $0.append(contentsOf: insertedEpisodeIDs) }
      if self.episodeIDs.first != previousHead {
        workStream.update(to: self.episodeIDs.first)
      }
      return self.episodeIDs.count
    }
    Self.log.debug(
      "enqueued \(insertedEpisodeIDs.count) episodes; depth \(depth)"
    )
  }

  @discardableResult
  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let currentEpisodeIDs = episodeIDs
    guard
      orderedEpisodeIDs.count == currentEpisodeIDs.count,
      Set(orderedEpisodeIDs) == Set(currentEpisodeIDs)
    else {
      Self.log.notice(
        """
        rejected reorder of \(orderedEpisodeIDs.count) ids; \
        current depth \(currentEpisodeIDs.count)
        """
      )
      return false
    }

    let accepted = try await store.reorder(orderedEpisodeIDs)
    guard accepted else {
      Self.log.notice(
        """
        skipped stale reorder of \(orderedEpisodeIDs.count) ids after \
        durable queue membership changed
        """
      )
      return false
    }

    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.new(orderedEpisodeIDs)
      if orderedEpisodeIDs.first != previousHead {
        workStream.update(to: orderedEpisodeIDs.first)
      }
    }
    Self.log.debug("reordered \(orderedEpisodeIDs.count) queued episodes")
    return true
  }

  func remove(_ episodeID: Episode.ID) async throws {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    try await store.remove(episodeID)
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      $interruptions.update { _ = $0.removeValue(forKey: episodeID) }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
  }

  func reconcileDeletion<Result: Sendable>(
    resolvingEpisodeIDs: () async throws -> Set<Episode.ID>,
    prepare: @Sendable (Set<Episode.ID>) async -> Void,
    perform deletion: () async throws -> Result
  ) async throws -> Result {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    let deletingEpisodeIDs = try await resolvingEpisodeIDs()
    let originalEpisodeIDs = mutationLock { _ in
      let originalEpisodeIDs = episodeIDs
      let previousHead = originalEpisodeIDs.first
      $episodeIDs.update {
        $0.removeAll { deletingEpisodeIDs.contains($0) }
      }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
      return originalEpisodeIDs
    }

    await prepare(deletingEpisodeIDs)

    do {
      let result = try await deletion()
      let depth = mutationLock { _ in
        $progress.update { progress in
          for episodeID in deletingEpisodeIDs {
            progress.removeValue(forKey: episodeID)
          }
        }
        $interruptions.update { interruptions in
          for episodeID in deletingEpisodeIDs {
            interruptions.removeValue(forKey: episodeID)
          }
        }
        $failed.update { $0.subtract(deletingEpisodeIDs) }
        return episodeIDs.count
      }
      Self.log.debug(
        """
        reconciled deletion of \(originalEpisodeIDs.count - depth) queued episodes; \
        depth \(depth)
        """
      )
      return result
    } catch {
      mutationLock { _ in
        let previousHead = episodeIDs.first
        $episodeIDs.new(originalEpisodeIDs)
        $progress.update { progress in
          for episodeID in deletingEpisodeIDs {
            progress.removeValue(forKey: episodeID)
          }
        }
        if episodeIDs.first != previousHead {
          workStream.update(to: episodeIDs.first)
        }
      }
      throw error
    }
  }

  func beginPausing(_ episodeID: Episode.ID) async throws -> Bool {
    await waitUntilLoaded()
    let shouldPause = mutationLock { _ in
      guard episodeIDs.contains(episodeID) else { return false }
      guard interruptions[episodeID] == nil else { return false }
      $interruptions.update { $0[episodeID] = .pausing }
      return true
    }
    guard shouldPause else { return false }

    let rollbackInterruption = {
      mutationLock { _ in
        guard interruptions[episodeID] == .pausing else { return }
        $interruptions.update { $0.removeValue(forKey: episodeID) }
      }
    }
    do {
      try await persistenceLock.waitForClaim()
    } catch {
      rollbackInterruption()
      throw error
    }
    defer { persistenceLock.release() }

    do {
      try await store.remove(episodeID)
    } catch {
      rollbackInterruption()
      throw error
    }

    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
    return true
  }

  func finishPausing(_ episodeID: Episode.ID) {
    mutationLock { _ in
      guard interruptions[episodeID] == .pausing else { return }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      $interruptions.update { _ = $0.removeValue(forKey: episodeID) }
    }
  }

  func beginDiscarding(_ episodeID: Episode.ID) async throws -> Bool {
    await waitUntilLoaded()
    let shouldDiscard = mutationLock { _ in
      guard interruptions[episodeID] == nil else { return false }
      $interruptions.update { $0[episodeID] = .discarding }
      return true
    }
    guard shouldDiscard else { return false }

    let rollbackInterruption = {
      mutationLock { _ in
        guard interruptions[episodeID] == .discarding else { return }
        $interruptions.update { $0.removeValue(forKey: episodeID) }
      }
    }
    do {
      try await persistenceLock.waitForClaim()
    } catch {
      rollbackInterruption()
      throw error
    }
    defer { persistenceLock.release() }

    do {
      try await store.remove(episodeID)
    } catch {
      rollbackInterruption()
      throw error
    }

    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      if episodeIDs.first != previousHead {
        workStream.update(to: episodeIDs.first)
      }
    }
    return true
  }

  func finishDiscarding(_ episodeID: Episode.ID) {
    mutationLock { _ in
      guard interruptions[episodeID] == .discarding else { return }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      $interruptions.update { _ = $0.removeValue(forKey: episodeID) }
      $failed.update { _ = $0.remove(episodeID) }
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

  func fail(_ episodeID: Episode.ID) async throws {
    await waitUntilLoaded()
    try await persistenceLock.waitForClaim()
    defer { persistenceLock.release() }

    try await store.remove(episodeID)
    mutationLock { _ in
      let previousHead = episodeIDs.first
      $episodeIDs.update { $0.removeAll { $0 == episodeID } }
      $progress.update { _ = $0.removeValue(forKey: episodeID) }
      $interruptions.update { _ = $0.removeValue(forKey: episodeID) }
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

  func status(
    for episodeID: Episode.ID,
    hasTranscript: Bool,
    checkpointProgress: Double? = nil
  ) -> TranscriptionStatus {
    if hasTranscript { return .transcribed }
    if let interruption = interruptions[episodeID] {
      switch interruption {
      case .pausing: return .pausing
      case .discarding: return .discarding
      }
    }
    if let value = progress[episodeID] { return .transcribing(value) }
    let queuedEpisodeIDs = episodeIDs
    if let index = queuedEpisodeIDs.firstIndex(of: episodeID) {
      return .queued(position: index + 1, total: queuedEpisodeIDs.count)
    }
    if failed.contains(episodeID) { return .failed }
    if let checkpointProgress { return .paused(checkpointProgress) }
    return .none
  }
}
