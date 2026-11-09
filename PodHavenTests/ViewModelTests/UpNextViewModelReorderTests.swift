// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of UpNextViewModel reorder tests", .container)
@MainActor final class UpNextViewModelReorderTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  // Regression: moveEpisode read the dragged row by index inside its Task, so a
  // queue emission landing first moved whichever episode had taken that index.
  @Test("moveEpisode moves the dragged episode even if the queue changes before it lands")
  func moveEpisodeMovesDraggedEpisodeAfterQueueEmission() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "first"),
          try Create.unsavedEpisode(guid: "second"),
          try Create.unsavedEpisode(guid: "third"),
        ]
      )
    )
    let ids = series.episodes.map(\.id)
    try await queue.append(ids)
    let queued = try await fetchListables(ids)

    let viewModel = UpNextViewModel()
    viewModel.episodeList.allEntries = IdentifiedArray(uniqueElements: queued)

    // Drag the first row to the end, then let a queue emission reorder the
    // rows before the move's Task runs.
    viewModel.moveEpisode(from: IndexSet(integer: 0), to: 3)
    viewModel.episodeList.allEntries = IdentifiedArray(
      uniqueElements: [queued[2], queued[0], queued[1]]
    )

    let expected = [ids[1], ids[2], ids[0]]
    try await Wait.until(
      { try await self.persistedQueueOrder(of: ids) == expected },
      {
        let order = try await self.persistedQueueOrder(of: ids)
        return "Expected the dragged episode to move to the end: \(expected); got \(order)"
      }
    )
    withExtendedLifetime(viewModel) {}
  }

  @Test("moveEpisode ignores a stale out-of-bounds source index")
  func moveEpisodeIgnoresStaleIndex() async throws {
    // No entries loaded, so any source index is stale.
    let viewModel = UpNextViewModel()

    viewModel.moveEpisode(from: IndexSet(integer: 0), to: 1)

    try await yieldForSpuriousAsyncWork()
    withExtendedLifetime(viewModel) {}
    let fakeQueue = try #require(queue as? FakeQueue)
    try fakeQueue.expectNoCall(methodName: "insert")
  }

  private func fetchListables(_ ids: [Episode.ID]) async throws -> [ListablePodcastEpisode] {
    try await repo.db.read { db in
      let byID =
        try ListablePodcastEpisode
        .request(filter: ids.contains(Episode.Columns.id))
        .fetchAll(db)
        .reduce(into: [Episode.ID: ListablePodcastEpisode]()) { $0[$1.id] = $1 }
      return ids.compactMap { byID[$0] }
    }
  }

  private func persistedQueueOrder(of ids: [Episode.ID]) async throws -> [Episode.ID] {
    try await fetchListables(ids)
      .sorted { ($0.queueOrder ?? Int.max) < ($1.queueOrder ?? Int.max) }
      .map(\.id)
  }
}
