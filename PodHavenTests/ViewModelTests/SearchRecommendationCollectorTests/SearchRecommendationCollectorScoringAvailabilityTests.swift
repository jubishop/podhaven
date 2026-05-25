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

    // Mirror AppLauncher: start the engine and let it rebuild with no signal
    // data. scoringRevision goes to >0 with hasScoringContext still false.
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in Container.shared.recommendationEngine().scoringRevision > 0 },
      { @Sendable in "Expected engine to publish a rebuild tick" }
    )
    #expect(!engine.hasScoringContext)

    let feedURL = FeedURL(URL(string: "https://example.com/pre-rebuilt-nil.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Pre Rebuilt Nil", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1602))]
    )

    // With the fix, awaitScoringContext sees scoringRevision > 0 + cache nil
    // and unblocks the drain immediately; processFeedURL fires the RSS
    // download. Without the fix, dropFirst() skips the bootstrap replay and
    // the drain stays blocked, so the RSS download never happens.
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in
        await Container.shared.podcastFeedSession() is FakeDataFetchable
          ? (Container.shared.podcastFeedSession() as! FakeDataFetchable).requests
            .contains(
              feedURL.rawValue
            ) : false
      },
      { @Sendable in "Expected RSS request after drain unblocked" }
    )

    #expect(collector.bannerState == .hidden)
  }

  // MARK: - Test: Cold Engine Defers Pipeline Until Hot

  @Test("recording before engine is hot yields picks once the engine warms")
  func recordingBeforeEngineHotEventuallyYieldsPicks() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    // Set up only the embedding factory. Do NOT seed signal episodes or
    // start the engine yet, so `hasScoringContext` stays false until we
    // explicitly prime it partway through the test.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let feedURL = FeedURL(URL(string: "https://example.com/cold-engine.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Cold Engine", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1001))]
    )
    try await H.advanceStableSourceDebounce()

    // Now hydrate the engine. Without the cold-engine gate, the pipeline
    // has already raced through scoring with a nil cache and marked the
    // entry `.scored` with no picks — and nothing retries it.
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

    // Set up the embedding factory but DO NOT seed any signal episodes — the
    // engine's buildContext consistently returns nil because there's no rated
    // / partial signal data. Without the fix, awaitScoringContext blocks
    // forever waiting for hasScoringContext, entries stay .pending, and the
    // banner is permanently .loading.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let feedURL = FeedURL(URL(string: "https://example.com/no-scoring.rss")!)
    await H.respondWithFeed(at: feedURL, title: "No Scoring", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1601))]
    )
    try await H.advanceStableSourceDebounce()

    // Wait for the reconcile to apply: feedURL lands in the source index with
    // a pending entry, banner enters .loading. Past this point the drain task
    // is blocked inside awaitScoringContext.
    try await Wait.until(
      { @MainActor in collector.bannerState == .loading },
      { @MainActor in
        "Expected banner to enter .loading after reconcile; got \(collector.bannerState)"
      }
    )

    // The drain task may not yet have reached engine.start() → observation →
    // scheduleCacheRebuild by the time the banner shows .loading. Wait for
    // the engine's cacheRebuild debounce to register its sleep before
    // advancing time, otherwise advanceTime jumps the clock past a not-yet-
    // scheduled wakeTime and the rebuild never fires.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    // Advance well beyond the cacheRebuild debounce. That fires buildContext
    // (returns nil) and bumps scoringRevision. With the fix, awaitScoringContext
    // returns and the banner transitions to .hidden; without it, the banner
    // stays .loading forever.
    await H.fakeSleeper.advanceTime(by: .seconds(10))
    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in
        "Expected banner to hide once scoring is determined unavailable, got \(collector.bannerState)"
      }
    )
  }
}
