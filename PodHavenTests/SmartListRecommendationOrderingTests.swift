// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Smart List raw recommendation ordering tests", .container)
@MainActor struct SmartListRecommendationOrderingTests {
  @Test(
    "phone and CarPlay retain raw ordering across display anchors and refresh scoring revisions",
    arguments: [
      SmartListFilter.StateCondition.isQueued, .isFinished, .isNotInterested,
    ]
  )
  func rawOrdering(state: SmartListFilter.StateCondition) async throws {
    try await CarPlaySmartListScene.clear()
    let engine = Container.shared.recommendationEngine()
    let repo = Container.shared.repo()
    let queue = Container.shared.queue()
    Container.shared.userSettings().$podcastAffinityWeight.new(1.0)
    let future: (Int) -> TimeInterval = { _ in 86400 }

    let (anchorPodcast, anchorSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Anchor",
      ratings: Array(repeating: .loved, count: 3)
    )
    let anchorCandidates = try await RecommendationHelpers.addEpisodes(
      to: anchorPodcast,
      count: 1,
      pubDateOffset: future
    )
    try await RecommendationHelpers.embedEpisodes(anchorSignals + anchorCandidates)

    let tag = try await repo.insertTag(UnsavedTag(name: "Ranked"))
    var targets: [Episode] = []
    var higherSignals: [Episode] = []
    var boosterID: Episode.ID?
    for signalCount in [5, 4] {
      let (podcast, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
        count: signalCount,
        podcastTitle: "Affinity \(signalCount)",
        ratings: Array(repeating: .loved, count: signalCount)
      )
      let episodes = try await RecommendationHelpers.addEpisodes(
        to: podcast,
        count: 1,
        ratings: state == .isNotInterested ? [.notInterested] : nil,
        finished: [state == .isFinished],
        pubDateOffset: future
      )
      try await RecommendationHelpers.embedEpisodes(signals + episodes)
      let episode = try #require(episodes.first)
      try await repo.addTag(tag.id, to: episode.id)
      if state == .isQueued { try await queue.append(episode.id) }
      targets.append(episode)

      if signalCount == 5 {
        higherSignals = signals
        let boosters = try await RecommendationHelpers.addEpisodes(
          to: podcast,
          count: 1,
          pubDateOffset: future
        )
        try await RecommendationHelpers.embedEpisodes(boosters)
        let booster = try #require(boosters.first)
        boosterID = booster.id
        try await queue.append(booster.id)
      }
    }

    let higher = targets[0]
    let lower = targets[1]
    let expected = targets.map(\.id)
    try #require(higher.id < lower.id, "The display-score tie must reverse the correct order")
    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let pool = try await engine.topRecommendations(limit: 100)
    try #require(Set(pool) == Set(anchorCandidates.map(\.id)))
    let raw = try await engine.unscaledRecommendationScores(forEpisodeIDs: expected)
    try #require(try #require(raw[higher.id]) > #require(raw[lower.id]))
    let anchorScores = try await engine.unscaledRecommendationScores(
      forEpisodeIDs: anchorCandidates.map(\.id)
    )
    try #require(try #require(raw[lower.id]) > #require(anchorScores.values.max()))
    let displayed = try await engine.recommendations(for: targets)
    try #require(displayed[higher.id]?.value == 1 && displayed[lower.id]?.value == 1)

    let definition = try await CarPlaySmartListScene.insert(
      "Ranked",
      sort: .recommendationScore,
      filter: SmartListFilter(conditions: [.tag(.hasTag(tag.id)), .state(state)])
    )
    let phone = EpisodesListViewModel(smartList: definition)
    let scene = try CarPlaySmartListScene()
    defer { scene.stop() }
    let detail = try await scene.open("Ranked")

    try await withRunningObservationLoop(phone) {
      try await Wait.until(
        { @MainActor in phone.loadingState == .loaded && phone.episodeList.allEntries.count == 2 },
        { "Phone Smart List must load both non-candidate episodes" }
      )
      #expect(phone.episodeList.allEntries.map(\.id) == expected)
      #expect(
        CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == expected
      )
      phone.episodeList.isSelected[higher.id] = true

      let revision = engine.scoringRevision
      try await queue.dequeue(try #require(boosterID))
      _ = try await engine.topRecommendations(limit: 100)
      let changedDisplay = try await engine.recommendations(for: targets)
      try #require(try #require(changedDisplay[lower.id]).value < 1)
      #expect(try await engine.unscaledRecommendationScores(forEpisodeIDs: expected) == raw)
      try await RecommendationScoringTestHelpers.settleRecommendationEngine()
      #expect(engine.scoringRevision == revision)
      #expect(phone.episodeList.allEntries.map(\.id) == expected)
      #expect(
        CarPlaySmartListScene.rows(detail).compactMap { $0.userInfo as? Episode.ID } == expected
      )
      #expect(phone.episodeList.isSelected[higher.id] == true)
    }

    // Re-enter the phone with its retained ranking and CarPlay with a fresh detail.
    scene.controller.goBack()
    let reopened = try await scene.open("Ranked")
    let observatory = try #require(Container.shared.observatory() as? FakeObservatory)
    observatory.clearAllCalls()
    try await withRunningObservationLoop(phone) {
      try await Wait.until(
        { @MainActor in
          phone.loadingState == .loaded && phone.episodeList.allEntries.count == 2
            && observatory.calls(of: MethodCall<Int>.self)
              .contains {
                $0.methodName == "listablePodcastEpisodes(filter:order:limit:)"
              }
        },
        { "Phone Smart List must restore its retained ranking" }
      )
      #expect(phone.episodeList.allEntries.map(\.id) == expected)
      #expect(
        CarPlaySmartListScene.rows(reopened).compactMap { $0.userInfo as? Episode.ID } == expected
      )

      let revision = engine.scoringRevision
      for signal in higherSignals {
        try await repo.updateRating(signal.id, rating: .disliked)
      }
      let reversed = Array(expected.reversed())
      try await RecommendationHelpers.untilAdvancing(
        { @MainActor in
          engine.scoringRevision > revision
            && phone.episodeList.allEntries.map(\.id) == reversed
            && CarPlaySmartListScene.rows(reopened).compactMap { $0.userInfo as? Episode.ID }
              == reversed
        },
        { "A real rating change must refresh raw ordering on both surfaces" }
      )
      #expect(scene.controller.topTemplate === reopened)
    }
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
  }
}
