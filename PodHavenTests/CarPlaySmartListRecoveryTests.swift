// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of CarPlay Smart List recovery tests", .container)
@MainActor struct CarPlaySmartListRecoveryTests {
  @Test("empty catalogs and failed queries are distinct and Retry restores the same root")
  func queryFailureAndEmpty() async throws {
    try await CarPlaySmartListScene.clear()
    let emptyScene = try CarPlaySmartListScene()
    try await Wait.until(
      { @MainActor in emptyScene.hub.emptyViewTitleVariants == ["No Smart Lists"] },
      { "Empty catalog must explain that no lists are saved" }
    )
    emptyScene.stop()
    _ = try await CarPlaySmartListScene.insert("Retry list")
    let db = Container.shared.appDB()
    try await db.writer.write { db in
      try db.execute(sql: "ALTER TABLE episode RENAME TO unavailableEpisode")
    }
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Retry list")
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(detail).contains { $0.text == "Retry" } },
      { "Failed episode query must expose Retry" }
    )
    #expect(CarPlaySmartListScene.rows(scene.hub).first?.detailText?.contains("0 unread") != true)
    try await db.writer.write { db in
      try db.execute(sql: "ALTER TABLE unavailableEpisode RENAME TO episode")
    }
    try CarPlaySmartListScene.tap("Retry", in: detail)
    try await Wait.until(
      { @MainActor in
        detail.itemCount == 0 && detail.emptyViewTitleVariants == ["No matching episodes"]
      },
      { "Retry must restore the actual empty result" }
    )
    #expect(scene.controller.roots.count == 1)
  }

  @Test("episode pages cover the complete result under restrictive budgets without stacking")
  func episodePaging() async throws {
    try await CarPlaySmartListScene.clear()
    _ = try await CarPlaySmartListScene.insert("Paged")
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 1) }
    }
    let series = try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisodes: try (0..<7)
            .map {
              try Create.unsavedEpisode(
                title: "Episode \($0)",
                pubDate: Date(timeIntervalSince1970: Double($0))
              )
            }
        )
      )
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Paged")
    var ids: [Episode.ID] = []
    for _ in 0..<4 {
      #expect(detail.itemCount <= 4)
      #expect(detail.sections.first?.header == "Paged")
      ids += CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID }
      if CarPlaySmartListScene.rows(detail).contains(where: { $0.text == "Next page" }) {
        try CarPlaySmartListScene.tap("Next page", in: detail)
      }
    }
    #expect(ids == series.episodes.sorted { $0.pubDate > $1.pubDate }.map(\.id))
    #expect(scene.controller.templates.count == 2)
  }

  @Test("a late old query cannot restore the previous definition or page")
  func delayedDefinition() async throws {
    try await CarPlaySmartListScene.clear()
    let list = try await CarPlaySmartListScene.insert("Delayed")
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    try await Wait.until(
      { @MainActor in CarPlaySmartListScene.rows(scene.hub).contains { $0.text == "Delayed" } },
      { "Hub must load before gating the episode query" }
    )
    let observatory = try #require(Container.shared.observatory() as? FakeObservatory)
    observatory.clearAllCalls()
    observatory.holdNextListablePodcastEpisodesDelivery()
    defer { observatory.releaseHeldListablePodcastEpisodesDelivery() }
    try CarPlaySmartListScene.tap("Delayed", in: scene.hub)
    let detail = try #require(scene.controller.topTemplate as? CPListTemplate)
    try await Wait.until(
      {
        !observatory.calls(of: MethodCall<Int>.self)
          .filter { $0.methodName == "listablePodcastEpisodes(filter:order:limit:)" }.isEmpty
      },
      { "Initial query must start before definition replacement" }
    )
    _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "Excluded"))
    try await Container.shared.smartListRepo()
      .update(
        list.id,
        title: "New definition",
        filter: SmartListFilter(conditions: [.state(.isFinished)]),
        showUnreadBadge: true,
        alwaysShowPodcastImage: false,
        icon: .listMusic
      )
    try await Wait.until(
      { @MainActor in
        !detail.showsSpinnerWhileEmpty && detail.emptyViewTitleVariants == ["No matching episodes"]
      },
      { "New query must settle without waiting for old delivery" }
    )
    observatory.releaseHeldListablePodcastEpisodesDelivery()
    let included = try await Create.podcastEpisode(
      Create.unsavedEpisode(title: "Included", finishDate: Date())
    )
    try await Wait.until(
      { @MainActor in
        CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == [
          included.id
        ]
      },
      { "Only the current definition may populate the destination" }
    )
  }

  @Test("recommendation sort preserves eligible candidates while cold and reranks when warm")
  func coldAndWarmRanking() async throws {
    try await CarPlaySmartListScene.clear()
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.8, 0.6, 0] }
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
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"],
      pubDateOffset: { Double(-$0 * 100) }
    )
    try await RecommendationHelpers.embedEpisodes(candidates, embeddable: embeddable)
    _ = try await CarPlaySmartListScene.episode(Create.unsavedEpisode(title: "No embedding"))
    let list = try await CarPlaySmartListScene.insert(
      "Ranked",
      sort: .recommendationScore,
      filter: EpisodesListTestHelpers.candidateFilter
    )
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Ranked")
    #expect(!Container.shared.recommendationEngine().hasScoringContext)
    #expect(
      CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID }
        == candidates.map(\.id)
    )
    #expect(detail.sections.contains { $0.header?.contains("newest first") == true })
    #expect(
      try await Container.shared.smartListRepo().fetchOne(list.id)?.sortMethod
        == .recommendationScore
    )
    let scores = try await RecommendationHelpers.startAndWaitForScores(for: candidates)
    let expected =
      candidates.sorted {
        let lhs = scores[$0.id]?.value ?? 0
        let rhs = scores[$1.id]?.value ?? 0
        return lhs == rhs ? $0.id > $1.id : lhs > rhs
      }
      .map(\.id)
    try #require(expected != candidates.map(\.id))
    try await Wait.until(
      { @MainActor in
        CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == expected
      },
      { "Warm cache must restore the phone's ranking" }
    )
    #expect(!detail.sections.contains { $0.header?.contains("newest first") == true })
    #expect(scene.controller.topTemplate === detail)
  }
}
