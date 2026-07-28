// Copyright Justin Bishop, 2026

@testable import PodHaven

struct FakeTranscriptionQueueStore: TranscriptionQueueStoring, Sendable {
  private struct State: Sendable {
    var episodeIDs: [Episode.ID]
    var fetchCount = 0
    var removeCalls: [Episode.ID] = []
  }

  private let state: ThreadSafe<State>
  private let beforeFetch: @Sendable () async throws -> Void
  private let beforeEnqueue: @Sendable ([Episode.ID]) async throws -> Void
  private let beforeRemove: @Sendable (Episode.ID) async throws -> Void

  init(
    episodeIDs: [Episode.ID] = [],
    beforeFetch: @escaping @Sendable () async throws -> Void = {},
    beforeEnqueue: @escaping @Sendable ([Episode.ID]) async throws -> Void = { _ in },
    beforeRemove: @escaping @Sendable (Episode.ID) async throws -> Void = { _ in }
  ) {
    state = ThreadSafe(State(episodeIDs: episodeIDs))
    self.beforeFetch = beforeFetch
    self.beforeEnqueue = beforeEnqueue
    self.beforeRemove = beforeRemove
  }

  var fetchCount: Int {
    state { $0.fetchCount }
  }

  var removeCalls: [Episode.ID] {
    state { $0.removeCalls }
  }

  func fetchAll() async throws -> [Episode.ID] {
    try await beforeFetch()
    return state { state in
      state.fetchCount += 1
      return state.episodeIDs
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
      return newEpisodeIDs
    }
  }

  func remove(_ episodeID: Episode.ID) async throws {
    try await beforeRemove(episodeID)
    state { state in
      state.removeCalls.append(episodeID)
      state.episodeIDs.removeAll { $0 == episodeID }
    }
  }

  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool {
    state { state in
      guard
        orderedEpisodeIDs.count == state.episodeIDs.count,
        Set(orderedEpisodeIDs) == Set(state.episodeIDs)
      else {
        return false
      }
      state.episodeIDs = orderedEpisodeIDs
      return true
    }
  }
}
