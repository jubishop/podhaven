// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of UpNextViewModel tests", .container)
@MainActor final class UpNextViewModelTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  @Test("recommended row hydration refreshes when cachedFilename updates")
  func recommendedHydrationRefreshesOnCacheChange() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "first", title: "First"),
          try Create.unsavedEpisode(guid: "second", title: "Second"),
        ]
      )
    )
    let first = series.episodes[0]
    let second = series.episodes[1]

    // Publish a ranking so the view model has something to hydrate.
    sharedState.setTopRecommendations([
      (id: first.id, score: RecommendationScore(value: 0.9, reasons: [])),
      (id: second.id, score: RecommendationScore(value: 0.8, reasons: [])),
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in
        "Expected 2 recommended episodes, got \(viewModel.recommendedEpisodes.count)"
      }
    )
    #expect(viewModel.recommendedEpisodes.map(\.id) == [first.id, second.id])
    #expect(viewModel.recommendedEpisodes[id: first.id]?.cacheStatus == .uncached)

    // Mutating the cache column on a recommended episode must refresh the
    // hydrated row — without the two-stage observation the view model would
    // freeze on the snapshot taken at publish time.
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET cachedFilename = ? WHERE id = ?",
        arguments: ["cached_first.mp3", first.id.rawValue]
      )
    }

    try await Wait.until(
      { @MainActor in
        viewModel.recommendedEpisodes[id: first.id]?.cacheStatus == .cached
      },
      { @MainActor in
        let status = viewModel.recommendedEpisodes[id: first.id]?.cacheStatus
        return "Expected first row to flip to .cached, got \(String(describing: status))"
      }
    )

    // saveInCache changes too — same hydration path.
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET saveInCache = ? WHERE id = ?",
        arguments: [true, second.id.rawValue]
      )
    }
    try await Wait.until(
      { @MainActor in
        viewModel.recommendedEpisodes[id: second.id]?.saveInCache == true
      },
      { @MainActor in
        let value = viewModel.recommendedEpisodes[id: second.id]?.saveInCache
        return "Expected second row saveInCache true, got \(String(describing: value))"
      }
    )
  }

  @Test("recommended hydration preserves rank order regardless of GRDB row order")
  func recommendedHydrationPreservesRankOrder() async throws {
    // Insert episodes with descending pubDate so GRDB's default ordering
    // returns them with the older one last; we publish the older one first
    // in the ranking and assert the rank order survives hydration.
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "newer", title: "Newer", pubDate: 1.daysAgo),
          try Create.unsavedEpisode(guid: "older", title: "Older", pubDate: 30.daysAgo),
        ]
      )
    )
    let newer = series.episodes[0]
    let older = series.episodes[1]

    // Older first, newer second — the engine's tiebreaker would normally
    // put newer first, but here we deliberately invert it to prove
    // hydration respects whatever order the engine published.
    sharedState.setTopRecommendations([
      (id: older.id, score: RecommendationScore(value: 0.9, reasons: [])),
      (id: newer.id, score: RecommendationScore(value: 0.8, reasons: [])),
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in "Hydration didn't populate; got \(viewModel.recommendedEpisodes.count)" }
    )
    #expect(viewModel.recommendedEpisodes.map(\.id) == [older.id, newer.id])
  }

  // Regression for #168: when the queue is empty, `maxQueuePosition` is nil
  // and unqueued episodes have `queueOrder == nil`. The old implementation
  // returned `nil == nil` → true, which hid "Queue at Bottom" from swipe
  // actions and context menus and made `queueEpisodeAtBottom` a silent no-op.
  @Test("isEpisodeAtBottomOfQueue is false for an unqueued episode when queue is empty")
  func isEpisodeAtBottomOfQueueFalseForUnqueuedWithEmptyQueue() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "unqueued", title: "Unqueued")]
      )
    )
    let unqueued = try await fetchListable(series.episodes[0].id)

    #expect(unqueued.queueOrder == nil)
    #expect(sharedState.maxQueuePosition == nil)

    let viewModel = UpNextViewModel()
    #expect(viewModel.isEpisodeAtBottomOfQueue(unqueued) == false)
  }

  // Recommended rows live outside the PowerList, so the default protocol
  // implementation (filter `episodeList.allEntries` by `isSelected`) misses
  // them. Verify the override unions queue + recs and that the predicates
  // the multi-select toolbar gates depend on follow.
  @Test("selectedEpisodes unions queued and recommended selections")
  func selectedEpisodesUnionsQueueAndRecommendations() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "queued", title: "Queued"),
          try Create.unsavedEpisode(guid: "rec", title: "Rec"),
        ]
      )
    )
    let queued = series.episodes[0]
    let rec = series.episodes[1]

    try await queue.append([queued.id])
    let queuedListable = try await fetchListable(queued.id)
    // StateManager isn't running in tests, so feed the queue broadcast
    // directly — same pattern as setTopRecommendations below.
    sharedState.setQueuedPodcastEpisodes([queuedListable])
    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 1
          && viewModel.recommendedEpisodes.count == 1
      },
      { @MainActor in
        "Expected queue=1 and recs=1, got queue=\(viewModel.episodeList.allEntries.count) "
          + "recs=\(viewModel.recommendedEpisodes.count)"
      }
    )

    let queuedRow = try #require(viewModel.episodeList.allEntries.first)
    let recRow = try #require(viewModel.recommendedEpisodes.first)

    viewModel.episodeList.isSelected[queuedRow.id] = true
    viewModel.episodeList.isSelected[recRow.id] = true

    let selectedIDs = Set(viewModel.selectedEpisodes.map(\.id))
    #expect(selectedIDs == [queuedRow.id, recRow.id])
    #expect(viewModel.anySelectedQueued)
    #expect(viewModel.anySelectedNotQueued)
  }

  @Test("recommendation-only selection counts as selected for toolbar actions")
  func recommendationOnlySelectionCountsForToolbarActions() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "rec", title: "Rec")]
      )
    )
    let rec = series.episodes[0]

    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 1 },
      { @MainActor in "Expected 1 rec, got \(viewModel.recommendedEpisodes.count)" }
    )
    let recRow = try #require(viewModel.recommendedEpisodes.first)
    viewModel.episodeList.setSelecting(true)
    viewModel.episodeList.isSelected[recRow.id] = true

    #expect(viewModel.anySelected)
    #expect(viewModel.anySelectedNotQueued)
  }

  @Test("Select All includes recommendation-only rows")
  func selectAllEntriesIncludesRecommendationOnlyRows() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "rec", title: "Rec")]
      )
    )
    let rec = series.episodes[0]

    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 1 },
      { @MainActor in "Expected 1 rec, got \(viewModel.recommendedEpisodes.count)" }
    )
    viewModel.episodeList.setSelecting(true)

    #expect(!viewModel.anySelected)
    #expect(viewModel.anyNotSelected)

    viewModel.selectAllEntries()

    #expect(viewModel.selectedEpisodes.map(\.id) == [rec.id])
    #expect(viewModel.anySelected)
    #expect(!viewModel.anyNotSelected)

    viewModel.unselectAllEntries()

    #expect(viewModel.selectedEpisodes.isEmpty)
    #expect(!viewModel.anySelected)
    #expect(viewModel.anyNotSelected)
  }

  @Test("Select All includes queued and recommended rows")
  func selectAllEntriesIncludesQueueAndRecommendations() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "queued", title: "Queued"),
          try Create.unsavedEpisode(guid: "rec", title: "Rec"),
        ]
      )
    )
    let queued = series.episodes[0]
    let rec = series.episodes[1]

    try await queue.append([queued.id])
    let queuedListable = try await fetchListable(queued.id)
    sharedState.setQueuedPodcastEpisodes([queuedListable])
    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 1
          && viewModel.recommendedEpisodes.count == 1
      },
      { @MainActor in "Expected hydration of queue + recs" }
    )
    let queuedRow = try #require(viewModel.episodeList.allEntries.first)
    let recRow = try #require(viewModel.recommendedEpisodes.first)
    viewModel.episodeList.setSelecting(true)

    #expect(!viewModel.anySelected)
    #expect(viewModel.anyNotSelected)

    viewModel.selectAllEntries()

    #expect(viewModel.selectedEpisodes.map(\.id) == [queuedRow.id, recRow.id])
    #expect(viewModel.anySelected)
    #expect(!viewModel.anyNotSelected)

    viewModel.unselectAllEntries()

    #expect(viewModel.selectedEpisodes.isEmpty)
    #expect(!viewModel.episodeList.isSelected[queuedRow.id])
    #expect(!viewModel.episodeList.isSelected[recRow.id])
    #expect(!viewModel.anySelected)
    #expect(viewModel.anyNotSelected)
  }

  // The new toolbar's "Add to Queue" path: selecting a rec and invoking the
  // bulk action must mark that rec as queued in the DB.
  @Test("addSelectedEpisodesToBottomOfQueue queues a selected recommendation")
  func addSelectedRecommendationToBottomOfQueue() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "rec", title: "Rec")]
      )
    )
    let rec = series.episodes[0]

    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 1 },
      { @MainActor in "Expected 1 rec, got \(viewModel.recommendedEpisodes.count)" }
    )
    let recRow = try #require(viewModel.recommendedEpisodes.first)
    viewModel.episodeList.isSelected[recRow.id] = true

    viewModel.addSelectedEpisodesToBottomOfQueue()

    try await Wait.until(
      { @MainActor in
        let listable = try await self.fetchListable(rec.id)
        return listable.queueOrder != nil
      },
      { @MainActor in
        let listable = try await self.fetchListable(rec.id)
        return
          "Expected rec \(rec.id) to land in queue; queueOrder=\(String(describing: listable.queueOrder))"
      }
    )
  }

  // replaceQueueWithSelected resolves `selectedPodcastEpisodes` for every
  // selected row and atomically rebuilds the queue from that list. If rec
  // resolution silently dropped a row, the queue would narrow rather than
  // crash — so assert both halves of a mixed selection land at distinct
  // queue positions.
  @Test("replaceQueueWithSelected rebuilds queue from queued + recommendation selection")
  func replaceQueueWithSelectedUnionsQueueAndRecommendations() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "queued", title: "Queued"),
          try Create.unsavedEpisode(guid: "rec", title: "Rec"),
        ]
      )
    )
    let queued = series.episodes[0]
    let rec = series.episodes[1]

    try await queue.append([queued.id])
    let queuedListable = try await fetchListable(queued.id)
    sharedState.setQueuedPodcastEpisodes([queuedListable])
    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 1
          && viewModel.recommendedEpisodes.count == 1
      },
      { @MainActor in "Expected hydration of queue + recs" }
    )

    let queuedRow = try #require(viewModel.episodeList.allEntries.first)
    let recRow = try #require(viewModel.recommendedEpisodes.first)
    viewModel.episodeList.isSelected[queuedRow.id] = true
    viewModel.episodeList.isSelected[recRow.id] = true

    viewModel.replaceQueueWithSelected()

    try await Wait.until(
      { @MainActor in
        let queuedAfter = try await self.fetchListable(queued.id)
        let recAfter = try await self.fetchListable(rec.id)
        return queuedAfter.queueOrder == 0 && recAfter.queueOrder == 1
      },
      { @MainActor in
        let queuedAfter = try await self.fetchListable(queued.id)
        let recAfter = try await self.fetchListable(rec.id)
        return """
          Expected queued at queueOrder=0 and rec at queueOrder=1; \
          got queued=\(String(describing: queuedAfter.queueOrder)) \
          rec=\(String(describing: recAfter.queueOrder))
          """
      }
    )
  }

  @Test("dequeueSelectedEpisodes ignores selected recommendations")
  func dequeueSelectedIgnoresRecommendations() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "queued", title: "Queued"),
          try Create.unsavedEpisode(guid: "rec", title: "Rec"),
        ]
      )
    )
    let queued = series.episodes[0]
    let rec = series.episodes[1]

    try await queue.append([queued.id])
    let queuedListable = try await fetchListable(queued.id)
    sharedState.setQueuedPodcastEpisodes([queuedListable])
    sharedState.setTopRecommendations([
      (id: rec.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 1
          && viewModel.recommendedEpisodes.count == 1
      },
      { @MainActor in "Expected hydration of queue + recs" }
    )

    let queuedRow = try #require(viewModel.episodeList.allEntries.first)
    let recRow = try #require(viewModel.recommendedEpisodes.first)
    viewModel.episodeList.isSelected[queuedRow.id] = true
    viewModel.episodeList.isSelected[recRow.id] = true

    viewModel.dequeueSelectedEpisodes()

    try await Wait.until(
      { @MainActor in
        let listable = try await self.fetchListable(queued.id)
        return listable.queueOrder == nil
      },
      { @MainActor in "Expected queued episode to be dequeued in DB" }
    )

    let recAfter = try await fetchListable(rec.id)
    #expect(recAfter.queueOrder == nil)

    // Pinpoint the regression: pre-fix code passed every saved selected ID
    // to queue.dequeue (including the recommendation). Assert directly that
    // only the queued ID reaches the queue so the test fails on the old path.
    let fakeQueue = try #require(queue as? FakeQueue)
    let dequeueCall = try fakeQueue.expectCall(
      methodName: "dequeue",
      parameters: [Episode.ID].self
    )
    #expect(dequeueCall.parameters == [queued.id])
  }

  // Race window: an episode is queued (so it shows up in episodeList) but the
  // recommendation engine hasn't re-ranked yet, so the same id is still in
  // topRecommendations. Selecting the id and replacing the queue must not
  // double-process — otherwise queue.replace sets queueOrder=1 and leaves
  // position 0 empty, breaking auto-advance (Queue.nextEpisode returns nil).
  @Test("selectedEpisodes dedupes when an id appears in both queue and recommendations")
  func selectedEpisodesDedupesQueueAndRecommendationOverlap() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "shared", title: "Shared")]
      )
    )
    let shared = series.episodes[0]

    try await queue.append([shared.id])
    let sharedListable = try await fetchListable(shared.id)
    sharedState.setQueuedPodcastEpisodes([sharedListable])
    sharedState.setTopRecommendations([
      (id: shared.id, score: RecommendationScore(value: 0.9, reasons: []))
    ])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 1
          && viewModel.recommendedEpisodes.count == 1
      },
      { @MainActor in
        "Expected id in both lists, got queue=\(viewModel.episodeList.allEntries.count) "
          + "recs=\(viewModel.recommendedEpisodes.count)"
      }
    )

    viewModel.episodeList.isSelected[shared.id] = true

    #expect(viewModel.selectedEpisodes.count == 1)
    #expect(viewModel.selectedEpisodes.first?.id == shared.id)

    viewModel.replaceQueueWithSelected()

    try await Wait.until(
      { @MainActor in
        let listable = try await self.fetchListable(shared.id)
        return listable.queueOrder == 0
      },
      { @MainActor in
        let listable = try await self.fetchListable(shared.id)
        return
          "Expected queueOrder=0 after replace, got \(String(describing: listable.queueOrder))"
      }
    )
  }

  private func fetchListable(_ episodeID: Episode.ID) async throws -> ListablePodcastEpisode {
    try await repo.db.read { db in
      let episode = try Episode.withID(episodeID)
        .including(required: Episode.podcast)
        .asRequest(of: ListablePodcastEpisode.self)
        .fetchOne(db)
      return try #require(episode)
    }
  }
}
