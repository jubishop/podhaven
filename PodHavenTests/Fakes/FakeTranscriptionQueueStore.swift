// Copyright Justin Bishop, 2026

@testable import PodHaven

struct FakeTranscriptionQueueStore: TranscriptionQueueStoring, Sendable {
  private struct State: Sendable {
    var episodeIDs: [Episode.ID]
    var workModes: [Episode.ID: TranscriptionWorkMode]
    var fetchCount = 0
    var removeCalls: [Episode.ID] = []
    var reorderCalls: [[Episode.ID]] = []
  }

  private let state: ThreadSafe<State>
  private let beforeFetch: @Sendable () async throws -> Void
  private let beforeEnqueue: @Sendable ([Episode.ID]) async throws -> Void
  private let beforeRemove: @Sendable (Episode.ID) async throws -> Void
  private let beforeReorder: @Sendable ([Episode.ID]) async throws -> Void
  private let afterReorder: @Sendable ([Episode.ID]) async throws -> Void

  init(
    episodeIDs: [Episode.ID] = [],
    workModes: [Episode.ID: TranscriptionWorkMode] = [:],
    beforeFetch: @escaping @Sendable () async throws -> Void = {},
    beforeEnqueue: @escaping @Sendable ([Episode.ID]) async throws -> Void = { _ in },
    beforeRemove: @escaping @Sendable (Episode.ID) async throws -> Void = { _ in },
    beforeReorder: @escaping @Sendable ([Episode.ID]) async throws -> Void = { _ in },
    afterReorder: @escaping @Sendable ([Episode.ID]) async throws -> Void = { _ in }
  ) {
    state = ThreadSafe(
      State(
        episodeIDs: episodeIDs,
        workModes: Dictionary(
          uniqueKeysWithValues: episodeIDs.map {
            ($0, workModes[$0] ?? .publisherPreferred)
          }
        )
      )
    )
    self.beforeFetch = beforeFetch
    self.beforeEnqueue = beforeEnqueue
    self.beforeRemove = beforeRemove
    self.beforeReorder = beforeReorder
    self.afterReorder = afterReorder
  }

  var fetchCount: Int {
    state { $0.fetchCount }
  }

  var removeCalls: [Episode.ID] {
    state { $0.removeCalls }
  }

  var reorderCalls: [[Episode.ID]] {
    state { $0.reorderCalls }
  }

  func fetchAll() async throws -> [TranscriptionWork] {
    try await beforeFetch()
    return state { state in
      state.fetchCount += 1
      return state.episodeIDs.map {
        TranscriptionWork(
          episodeID: $0,
          mode: state.workModes[$0] ?? .publisherPreferred
        )
      }
    }
  }

  func enqueue(
    _ episodeIDs: [Episode.ID],
    maximumCount: Int
  ) async throws -> [Episode.ID] {
    try await beforeEnqueue(episodeIDs)
    return try state { state in
      var seen = Set<Episode.ID>()
      let newEpisodeIDs = episodeIDs.filter {
        seen.insert($0).inserted && !state.episodeIDs.contains($0)
      }
      guard !newEpisodeIDs.isEmpty else { return [] }
      guard state.episodeIDs.count + newEpisodeIDs.count <= maximumCount else {
        throw TranscriptionQueueError.capacityExceeded(
          limit: maximumCount,
          currentCount: state.episodeIDs.count,
          requestedCount: newEpisodeIDs.count
        )
      }
      state.episodeIDs.append(contentsOf: newEpisodeIDs)
      for episodeID in newEpisodeIDs {
        state.workModes[episodeID] = .publisherPreferred
      }
      return newEpisodeIDs
    }
  }

  func enqueueReplacement(
    _ episodeID: Episode.ID,
    maximumCount: Int
  ) async throws -> Bool {
    try await beforeEnqueue([episodeID])
    return try state { state in
      if state.episodeIDs.contains(episodeID) {
        state.workModes[episodeID] = .onDeviceReplacement
        return false
      }
      guard state.episodeIDs.count < maximumCount else {
        throw TranscriptionQueueError.capacityExceeded(
          limit: maximumCount,
          currentCount: state.episodeIDs.count,
          requestedCount: 1
        )
      }
      state.episodeIDs.append(episodeID)
      state.workModes[episodeID] = .onDeviceReplacement
      return true
    }
  }

  func remove(_ episodeID: Episode.ID) async throws {
    try await beforeRemove(episodeID)
    state { state in
      state.removeCalls.append(episodeID)
      state.episodeIDs.removeAll { $0 == episodeID }
      state.workModes.removeValue(forKey: episodeID)
    }
  }

  func remove(
    _ episodeID: Episode.ID,
    ifMode mode: TranscriptionWorkMode
  ) async throws -> Bool {
    try await beforeRemove(episodeID)
    return state { state in
      state.removeCalls.append(episodeID)
      guard state.workModes[episodeID] == mode else { return false }
      state.episodeIDs.removeAll { $0 == episodeID }
      state.workModes.removeValue(forKey: episodeID)
      return true
    }
  }

  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool {
    state { $0.reorderCalls.append(orderedEpisodeIDs) }
    try await beforeReorder(orderedEpisodeIDs)
    let accepted = state { state in
      guard
        orderedEpisodeIDs.count == state.episodeIDs.count,
        Set(orderedEpisodeIDs) == Set(state.episodeIDs)
      else {
        return false
      }
      state.episodeIDs = orderedEpisodeIDs
      return true
    }
    guard accepted else { return false }
    try await afterReorder(orderedEpisodeIDs)
    return true
  }
}
