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
  @DynamicInjected(\.repo) private var repo

  // MARK: - Test: Banner Hides And No RSS When Engine Pre-Rebuilt To Nil

  // The drain must block on awaitScoringContext rather than proceed and
  // discard every score. Otherwise a new user (no ratings → no context)
  // browsing trending chips silently fetches RSS for every podcast they
  // pass over, then re-fetches everything when the engine eventually warms.
  @Test("banner hides and no RSS fires when engine rebuilt to no context")
  func bannerHidesAndNoRSSWhenEnginePreRebuiltToNil() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

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
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in "Expected banner to hide; got \(collector.bannerState)" }
    )

    let requests = await H.session.requests
    #expect(
      !requests.contains(feedURL.rawValue),
      "Expected no RSS request while scoring is unavailable; got \(requests)"
    )
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

  // MARK: - Test: Discovery List Reads Loading While Picks Still Drain

  // An empty pick set during an active drain must surface `.loading`, not
  // `.empty` — otherwise the discovery list shows its worked-through-all
  // placeholder while more picks are still being fetched and scored.
  @Test("discovery list state is loading while picks are still draining")
  func discoveryListStateLoadingWhileDraining() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    // Embedding factory only — no signal episodes and no sleeper advance past
    // the cacheRebuild debounce, so the drain blocks on awaitScoringContext
    // with the entry `.pending`: picks stay empty while the banner is loading.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    engine.start()

    let feedURL = FeedURL(URL(string: "https://example.com/draining.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Draining", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1701))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.bannerState == .loading },
      { @MainActor in
        "Expected banner to enter .loading after reconcile; got \(collector.bannerState)"
      }
    )

    #expect(collector.picks(for: source).isEmpty)
    #expect(collector.discoveryListState(for: source) == .loading)
  }

  // MARK: - Test: Banner Reflects A Cooled Engine

  // Once the engine cools (signals cleared → rebuild yields no context), a
  // zero-pick source must hide its banner rather than keep showing a loading
  // spinner that cannot complete until the engine warms again.
  @Test("banner hides when the engine cools while a fetch is still in flight")
  func bannerHidesWhenEngineCoolsMidDrain() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

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

    // Park the RSS fetch on a semaphore so the entry stays .fetching (and the
    // banner .loading) across the cool-down below.
    let feedURL = FeedURL(URL(string: "https://example.com/cooled-mid-drain.rss")!)
    let release = await H.session.waitRespond(to: feedURL.rawValue)
    defer { release.signal() }

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1801))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.bannerState == .loading },
      { @MainActor in
        "Expected banner to load while the fetch hangs; got \(collector.bannerState)"
      }
    )

    for signal in signals {
      _ = try await repo.updateRating(signal.id, rating: nil)
    }
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in !localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to close after unrating signals" }
    )

    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in
        "Expected banner to hide once the engine cooled, got \(collector.bannerState)"
      }
    )
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

  // MARK: - Test: A Podcast-Embedding Failure Stays Recoverable

  // The podcast-context vector is computed once per feed instead of inside the
  // per-episode loop. A failure there must not collapse the whole feed to a
  // terminal `.failed`: the per-episode path it replaces skipped each episode
  // and finished empty-and-`.scored`, which a later scoring-context reopen
  // re-drains. `.failed` is excluded from that retry, so a model that was
  // briefly unavailable would never recover the feed's picks for the
  // collector's lifetime.
  @Test("a podcast-embedding failure leaves the feed recoverable, not terminal .failed")
  func podcastEmbeddingFailureStaysRecoverable() async throws {
    let collector = SearchRecommendationCollector()
    // Throw for the candidate feed's podcast title/description only (episode
    // titles carry "Pick"), so the podcast-context vector fails while the
    // signal and candidate embeds still succeed.
    let scripted = ScriptedEmbeddable(
      errorFor: { text in
        text.contains("Embed Fails") && !text.contains("Pick") ? EmbeddingProbeError() : nil
      }
    ) { text in
      if text.contains("Below Floor") { return [-1, 0, 0] }
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }

    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

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

    let feedURL = FeedURL(URL(string: "https://example.com/embed-fails.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Embed Fails", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1901))]
    )
    try await H.advanceStableSourceDebounce()

    // The feed fetches once, the podcast embed throws, and it settles with no
    // picks — banner hidden in both the recoverable and the terminal cases.
    try await Wait.until(
      { @MainActor in await H.session.requests.contains(feedURL.rawValue) },
      { @MainActor in "Expected the embed-failing feed to be fetched once" }
    )
    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in "Expected the feed to settle with no picks; got \(collector.bannerState)" }
    )
    let initialRequests = await H.session.requests.filter { $0 == feedURL.rawValue }.count
    #expect(initialRequests == 1, "Test premise: exactly one RSS request before the cycle")

    // Drive scoring close → open; the open edge fires
    // handleScoringContextBecameAvailable, which re-drains empty-`.scored` feeds.
    for signal in signals {
      _ = try await repo.updateRating(signal.id, rating: nil)
    }
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in !localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to close after unrating signals" }
    )
    let restoredRatings: [EpisodeRating] = [.loved, .liked, .liked]
    for (signal, rating) in zip(signals, restoredRatings) {
      _ = try await repo.updateRating(signal.id, rating: rating)
    }
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to reopen after re-rating signals" }
    )

    // A recoverable empty-`.scored` feed re-drains on the reopen and fetches
    // again; a terminal `.failed` feed (the regression) never would.
    try await Wait.until(
      { @MainActor in await H.session.requests.filter { $0 == feedURL.rawValue }.count == 2 },
      { @MainActor in "Expected the embed-failed feed to re-fetch after scoring reopened" }
    )
  }
}

// Distinct error so the scripted embeddable can simulate an embedding failure.
private struct EmbeddingProbeError: Error {}
