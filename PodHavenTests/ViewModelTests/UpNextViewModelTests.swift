// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of UpNextViewModel tests", .container)
@MainActor final class UpNextViewModelTests {
  @DynamicInjected(\.appDB) private var appDB
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
}
