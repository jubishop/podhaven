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
  @DynamicInjected(\.stateManager) private var stateManager

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
    sharedState.setRecommendedEpisodePool([first.id, second.id])

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
    try await appDB.unsafeTestDB.write { db in
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
    try await appDB.unsafeTestDB.write { db in
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
    sharedState.setRecommendedEpisodePool([older.id, newer.id])

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
    // directly — same pattern as setRecommendedEpisodePool below.
    sharedState.setQueuedPodcastEpisodes([queuedListable])
    sharedState.setRecommendedEpisodePool([rec.id])

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

    sharedState.setRecommendedEpisodePool([rec.id])

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

    sharedState.setRecommendedEpisodePool([rec.id])

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
    sharedState.setRecommendedEpisodePool([rec.id])

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

    sharedState.setRecommendedEpisodePool([rec.id])

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
    sharedState.setRecommendedEpisodePool([rec.id])

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
    sharedState.setRecommendedEpisodePool([rec.id])

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

  // Regression for #338: queueing one of the published recommended episodes
  // must drop it from `recommendedEpisodes` immediately, without waiting for
  // the engine's debounced rebuild. The pool publishes IDs; the view model is
  // responsible for filtering candidate-ineligible rows locally.
  @Test("recommended row drops a queued episode instantly")
  func recommendedDropsQueuedEpisodeInstantly() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "a", title: "A"),
          try Create.unsavedEpisode(guid: "b", title: "B"),
        ]
      )
    )
    let a = series.episodes[0]
    let b = series.episodes[1]

    sharedState.setRecommendedEpisodePool([a.id, b.id])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in "Hydration didn't populate; got \(viewModel.recommendedEpisodes.count)" }
    )

    try await queue.append([a.id])

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [b.id] },
      { @MainActor in
        "Expected only [b] after queueing a, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )
  }

  // Regression for #338: rating a recommended episode must drop it instantly.
  // The candidate gate excludes rated episodes; the view model's filter must
  // honor that without waiting for a recommendation-pool rebuild.
  @Test("recommended row drops a rated episode instantly")
  func recommendedDropsRatedEpisodeInstantly() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "a", title: "A"),
          try Create.unsavedEpisode(guid: "b", title: "B"),
        ]
      )
    )
    let a = series.episodes[0]
    let b = series.episodes[1]

    sharedState.setRecommendedEpisodePool([a.id, b.id])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in "Hydration didn't populate; got \(viewModel.recommendedEpisodes.count)" }
    )

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET rating = ?, ratingDate = ? WHERE id = ?",
        arguments: [EpisodeRating.liked.rawValue, Date(), a.id.rawValue]
      )
    }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [b.id] },
      { @MainActor in
        "Expected only [b] after rating a, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )
  }

  // Regression for #338: finishing a recommended episode must drop it
  // instantly. Same shape as rating — different gate column.
  @Test("recommended row drops a finished episode instantly")
  func recommendedDropsFinishedEpisodeInstantly() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "a", title: "A"),
          try Create.unsavedEpisode(guid: "b", title: "B"),
        ]
      )
    )
    let a = series.episodes[0]
    let b = series.episodes[1]

    sharedState.setRecommendedEpisodePool([a.id, b.id])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in "Hydration didn't populate; got \(viewModel.recommendedEpisodes.count)" }
    )

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET finishDate = ? WHERE id = ?",
        arguments: [Date(), a.id.rawValue]
      )
    }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [b.id] },
      { @MainActor in
        "Expected only [b] after finishing a, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )
  }

  // Regression for #338: the currently-playing episode must not appear
  // in the recommended row, even if it's still in the published pool.
  @Test("recommended row drops the current episode instantly")
  func recommendedDropsCurrentEpisodeInstantly() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "a", title: "A"),
          try Create.unsavedEpisode(guid: "b", title: "B"),
        ]
      )
    )
    let a = series.episodes[0]
    let b = series.episodes[1]

    sharedState.setRecommendedEpisodePool([a.id, b.id])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 2 },
      { @MainActor in "Hydration didn't populate; got \(viewModel.recommendedEpisodes.count)" }
    )

    let aPodcastEpisode = try #require(try await repo.podcastEpisode(a.id))
    stateManager.setOnDeck(aPodcastEpisode)

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [b.id] },
      { @MainActor in
        "Expected only [b] after current episode = a, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )
  }

  // Regression for #338: changing the user's "Recommended Episodes" slider
  // must re-slice the visible row instantly — no engine rebuild required.
  @Test("recommended row reslices when maxRecommendedEpisodesInUpNext changes")
  func recommendedReslicesOnSettingChange() async throws {
    let userSettings = Container.shared.userSettings()
    userSettings.$maxRecommendedEpisodesInUpNext.new(6)
    defer { userSettings.$maxRecommendedEpisodesInUpNext.new(5) }

    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: (0..<6)
          .map { idx in
            try Create.unsavedEpisode(guid: "e\(idx)", title: "E\(idx)")
          }
      )
    )
    let ids = series.episodes.map(\.id)

    sharedState.setRecommendedEpisodePool(ids)

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.count == 6 },
      { @MainActor in
        "Expected 6 visible at N=6, got \(viewModel.recommendedEpisodes.count)"
      }
    )

    userSettings.$maxRecommendedEpisodesInUpNext.new(2)

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == Array(ids.prefix(2)) },
      { @MainActor in
        "Expected first 2 visible at N=2, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )
  }

  // Regression: if the pool transitions to an overlapping ranking
  // ([A, B] -> [B, C]) while a concurrent observer (currentEpisodeID) forces
  // a local rebuild during the hydration gap, the recommended row must not
  // flash to empty. Overlap on B has to survive the pool swap.
  @Test("recommended row keeps overlap during pool transition with concurrent rebuild")
  func recommendedKeepsOverlapDuringConcurrentRebuild() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "a", title: "A"),
          try Create.unsavedEpisode(guid: "b", title: "B"),
          try Create.unsavedEpisode(guid: "c", title: "C"),
          try Create.unsavedEpisode(guid: "d", title: "D"),
        ]
      )
    )
    let a = series.episodes[0]
    let b = series.episodes[1]
    let c = series.episodes[2]
    let d = series.episodes[3]

    sharedState.setRecommendedEpisodePool([a.id, b.id])

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [a.id, b.id] },
      { @MainActor in
        "Initial pool [A, B] didn't hydrate, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )

    let snapshots = ThreadSafe<[[Episode.ID]]>([])
    let tracker = Task { @MainActor in
      while !Task.isCancelled {
        let snapshot = viewModel.recommendedEpisodes.map(\.id)
        snapshots { $0.append(snapshot) }
        await Task.yield()
      }
    }
    defer { tracker.cancel() }

    sharedState.setRecommendedEpisodePool([b.id, c.id])
    let dPodcastEpisode = try #require(try await repo.podcastEpisode(d.id))
    stateManager.setOnDeck(dPodcastEpisode)

    try await Wait.until(
      { @MainActor in viewModel.recommendedEpisodes.map(\.id) == [b.id, c.id] },
      { @MainActor in
        "Final pool [B, C] didn't settle, got \(viewModel.recommendedEpisodes.map(\.id))"
      }
    )

    tracker.cancel()

    let recorded = snapshots()
    let flashedEmpty = recorded.contains { $0.isEmpty }
    #expect(
      !flashedEmpty,
      """
      Recommended row flashed empty during overlapping pool transition; B should \
      have stayed visible. Recorded sequence: \(recorded)
      """
    )
  }

  // Issue #411: UpNext gains a recommendation-score sort that persists the
  // reordered queue. Unlike the EpisodesList/PodcastDetail rec sorts, the
  // queued episodes are not candidates (they're queued), so the engine must
  // score them anyway and the new order has to land in the DB.
  @Test("recommendationScore sort persists the queue in score-descending order")
  func recommendationScoreSortPersistsScoreDescendingOrder() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // Spread the queued episodes across two podcasts so the sort has to look
    // up each row's own podcastID for the engine's affinity/freshness inputs.
    let (_, podcastA) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target A",
      podcastDescription: "Target A",
      episodeDescriptions: ["Target 0", "Target 3"]
    )
    try await RecommendationHelpers.embedEpisodes(podcastA, embeddable: embeddable)

    let (_, podcastB) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target B",
      podcastDescription: "Target B",
      episodeDescriptions: ["Target 1", "Target 2"]
    )
    try await RecommendationHelpers.embedEpisodes(podcastB, embeddable: embeddable)

    let targets = podcastA + podcastB
    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    let expectedOrder =
      targets
      .sorted { lhs, rhs in
        let lhsScore = scoreMap[lhs.id]?.value ?? 0
        let rhsScore = scoreMap[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
        return lhs.id > rhs.id
      }
      .map(\.id)

    // Queue the targets in their original (non-score) order so a successful
    // sort has to actually reorder the persisted queue.
    let queuedOrder = targets.map(\.id)
    try #require(
      expectedOrder != queuedOrder,
      "Score order matched the initial queue order; the test wouldn't prove the sort applied."
    )
    try await queue.append(queuedOrder)
    sharedState.setQueuedPodcastEpisodes(try await fetchListables(queuedOrder))

    let viewModel = UpNextViewModel()
    let executeTask = Task { await viewModel.execute() }
    defer { executeTask.cancel() }

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.map(\.id) == queuedOrder },
      { @MainActor in
        "Queue didn't hydrate in append order, got \(viewModel.episodeList.allEntries.map(\.id))"
      }
    )

    viewModel.sort(by: .recommendationScore)

    try await Wait.until(
      { @MainActor in try await self.persistedQueueOrder(of: queuedOrder) == expectedOrder },
      { @MainActor in
        """
        Expected persisted queue in score order \(expectedOrder), \
        got \(try await self.persistedQueueOrder(of: queuedOrder))
        """
      }
    )

    let fakeQueue = try #require(queue as? FakeQueue)
    let updateCall = try fakeQueue.expectCall(
      methodName: "updateQueueOrders",
      parameters: [Episode.ID].self
    )
    #expect(updateCall.parameters == expectedOrder)
  }

  // Issue #411: because UpNext persists the sort, the rec-score option stays
  // hidden until the engine's scoring cache is warm (a cold cache would score
  // everything 0 and scramble the saved queue). The base options are always
  // offered.
  @Test("recommendationScore sort option appears only once the scoring cache is warm")
  func recommendationScoreSortHiddenUntilScoringCacheWarms() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Signal") { return [1, 0, 0] }
      return [0, 0, 1]
    }
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let viewModel = UpNextViewModel()

    // Engine not started yet: cache cold, option hidden, base options present.
    #expect(viewModel.allSortMethods.contains(.newestFirst))
    #expect(!viewModel.allSortMethods.contains(.recommendationScore))

    // Warming the engine flips the observable flag and reveals the option.
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signals)
    #expect(viewModel.allSortMethods.contains(.recommendationScore))
  }

  private func fetchListable(_ episodeID: Episode.ID) async throws -> ListablePodcastEpisode {
    try await repo.db.read { db in
      let episode =
        try ListablePodcastEpisode
        .request(filter: Episode.Columns.id == episodeID)
        .fetchOne(db)
      return try #require(episode)
    }
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
