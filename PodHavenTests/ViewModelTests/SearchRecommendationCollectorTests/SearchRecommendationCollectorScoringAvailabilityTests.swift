// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector scoring availability tests", .container)
@MainActor final class SearchRecommendationCollectorScoringAvailabilityTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  @DynamicInjected(\.recommendationEngine) private var engine

  // MARK: - Test: Banner Hides When Engine Pre-Rebuilt To Nil

  @Test("banner hides when engine rebuilt to no context before collector subscribed")
  func bannerHidesWhenEnginePreRebuiltToNil() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    // Mirror AppLauncher: start with no signal data so scoringRevision goes
    // to >0 with hasScoringContext still false.
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in Container.shared.recommendationEngine().scoringRevision > 0 },
      { @Sendable in "Expected engine to publish a rebuild tick" }
    )
    #expect(!engine.hasScoringContext)

    let feedURL = FeedURL(URL(string: "https://example.com/pre-rebuilt-nil.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Pre Rebuilt Nil", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1602))]
    )

    // awaitScoringContext must see the bootstrap replay (no dropFirst) so
    // the drain unblocks and processFeedURL fires the RSS download.
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in await H.session.requests.contains(feedURL.rawValue) },
      { @Sendable in "Expected RSS request after drain unblocked" }
    )

    #expect(collector.bannerState == .hidden)
  }

  // MARK: - Test: Cold Engine Defers Pipeline Until Hot

  @Test("recording before engine is hot yields picks once the engine warms")
  func recordingBeforeEngineHotEventuallyYieldsPicks() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    // Embedding factory only — no signal episodes / no engine start, so
    // `hasScoringContext` stays false until we prime it midway.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let feedURL = FeedURL(URL(string: "https://example.com/cold-engine.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Cold Engine", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1001))]
    )
    try await H.advanceStableSourceDebounce()

    // Hydrate after the reconcile — without the cold-engine gate the
    // pipeline would have raced through with a nil cache and marked the
    // entry `.scored` with no picks.
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: scripted)
    let localEngine = Container.shared.recommendationEngine()
    localEngine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected picks once engine warmed; got \(collector.bannerState)" }
    )
    #expect(!collector.visiblePicks.isEmpty)
  }

  // MARK: - Test: Banner Hides When Engine Cannot Build A Scoring Context

  @Test("banner hides when the engine cannot build a scoring context")
  func bannerHidesWhenScoringUnavailable() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    // No signal episodes — engine.buildContext returns nil indefinitely.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    // Mirror AppLauncher: start the engine before the collector subscribes so
    // the bootstrap cacheRebuild has a sleep request to wait on below.
    engine.start()

    let feedURL = FeedURL(URL(string: "https://example.com/no-scoring.rss")!)
    await H.respondWithFeed(at: feedURL, title: "No Scoring", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1601))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.bannerState == .loading },
      { @MainActor in
        "Expected banner to enter .loading after reconcile; got \(collector.bannerState)"
      }
    )

    // Wait for the cacheRebuild sleep to register before advancing — otherwise
    // advanceTime jumps past a not-yet-scheduled wakeTime and rebuild never fires.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    // Advance past the cacheRebuild debounce so scoringRevision ticks; banner
    // transitions to .hidden.
    await H.fakeSleeper.advanceTime(by: .seconds(10))
    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in
        "Expected banner to hide once scoring is determined unavailable, got \(collector.bannerState)"
      }
    )
  }
}
