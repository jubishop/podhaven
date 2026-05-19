// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import IdentifiedCollections
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector tests", .container)
@MainActor final class SearchRecommendationCollectorTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  // MARK: - Test: Happy Path

  @Test("recordSourcePodcasts → picks land after stable-source debounce")
  func happyPath() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/discovery.rss")!)
    await respondWithFeed(at: feedURL, title: "Discovery", episodes: 3)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(101))]
    )

    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in
        "Expected banner to load with picks, got \(collector.bannerState)"
      }
    )
    #expect(!collector.visiblePicks.isEmpty)
  }

  // MARK: - Test: Stable-Source Debounce

  @Test("stable-source debounce holds RSS fan-out for 1 s")
  func stableSourceDebounce() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/slow.rss")!)
    await respondWithFeed(at: feedURL, title: "Slow", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(202))]
    )

    // Before advancing the debouncer, no RSS request should have happened.
    try await fakeSleeper.waitForSleepRequests(count: 1)
    let earlyRequests = await session.requests
    #expect(!earlyRequests.contains(feedURL.rawValue))

    await fakeSleeper.advanceTime(by: .seconds(1))

    try await Wait.until(
      { @MainActor in await self.session.requests.contains(feedURL.rawValue) },
      { @MainActor in
        let r = await self.session.requests
        return "Expected RSS request for \(feedURL.rawValue); got \(r)"
      }
    )
  }

  // MARK: - Test: Subscribed Exclusion via iTunesID Reconciliation

  @Test("subscribed podcast is excluded after DB reconciliation by iTunes ID")
  func subscribedExclusionByITunesID() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let canonicalFeedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchFeedURL = FeedURL(URL(string: "https://example.com/search-row.rss")!)
    let iTunesID = ITunesPodcastID(909)

    // Pre-insert a subscribed podcast with a DIFFERENT feedURL but matching
    // iTunesID — collector must reconcile by iTunes ID and drop it.
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: canonicalFeedURL,
          iTunesID: iTunesID,
          title: "Subscribed Canon",
          subscriptionDate: Date()
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Subscribed Ep")]
      )
    )

    let alsoUnsubscribedFeedURL = FeedURL(URL(string: "https://example.com/pass.rss")!)
    await respondWithFeed(at: alsoUnsubscribedFeedURL, title: "Pass-Through", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: 1303, title: "Comedy")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [
        makeUnsavedRow(feedURL: searchFeedURL, iTunesID: iTunesID),
        makeUnsavedRow(feedURL: alsoUnsubscribedFeedURL, iTunesID: ITunesPodcastID(910)),
      ]
    )

    try await advanceStableSourceDebounce()

    // Wait for the only un-subscribed entry to land.
    try await Wait.until(
      { @MainActor in
        if case .loaded = collector.bannerState { return true }
        return false
      },
      { @MainActor in "Expected at least one pick, got \(collector.bannerState)" }
    )

    // The subscribed canonical feed must never have been requested.
    let requests = await session.requests
    #expect(!requests.contains(canonicalFeedURL.rawValue))
    #expect(!requests.contains(searchFeedURL.rawValue))
    #expect(requests.contains(alsoUnsubscribedFeedURL.rawValue))
  }

  // MARK: - Test: Candidate Gate Filters Rated Episodes

  @Test("candidate gate drops episodes matching a rated DB row")
  func candidateGateFiltersRatedEpisodes() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/gated.rss")!)

    // Pre-insert an unsubscribed-but-saved podcast whose existing episode row
    // matches one of the RSS GUIDs and is RATED → must be dropped by the gate.
    let ratedGUID = GUID("gated-ep-rated")
    let unsavedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: ITunesPodcastID(303),
          title: "Gated",
          subscriptionDate: nil
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: ratedGUID, title: "Already Rated", rating: .disliked)
        ]
      )
    )

    // Sanity: not subscribed.
    #expect(unsavedSeries.podcast.subscriptionDate == nil)

    // RSS provides two episodes — one with matching guid (rated), one new.
    await session.respond(
      to: feedURL.rawValue,
      data: rssXML(
        title: "Gated",
        feedURL: feedURL,
        episodes: [
          ("gated-ep-rated", "Already Rated", Date(timeIntervalSince1970: 1_700_000_000)),
          ("gated-ep-new", "Fresh Episode", Date(timeIntervalSince1970: 1_800_000_000)),
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(genreID: 1303, title: "Comedy")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(303))]
    )

    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected at least one pick, got \(collector.bannerState)" }
    )

    // The rated episode's GUID must not appear in the visible picks.
    let guids = collector.visiblePicks.map(\.episode.mediaGUID.guid.rawValue)
    #expect(!guids.contains("gated-ep-rated"))
    #expect(guids.contains("gated-ep-new"))
  }

  // MARK: - Test: Score Ordering

  @Test("score floor filters episodes whose similarity is too low")
  func scoreOrdering() async throws {
    // The signal centroid is built from three orthogonal signals, so the
    // discovery candidates' default direction lands above the 0.5 floor and
    // anything anti-aligned ("Below Floor") gets filtered out.
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/order.rss")!)
    await session.respond(
      to: feedURL.rawValue,
      data: rssXML(
        title: "Order",
        feedURL: feedURL,
        episodes: [
          ("ord-default", "Aligned Pick", Date(timeIntervalSince1970: 1_900_000_000)),
          ("ord-floor", "Below Floor Pick", Date(timeIntervalSince1970: 2_000_000_000)),
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(404))]
    )

    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        guard case .loaded(let count) = collector.bannerState else { return false }
        return count >= 1
      },
      { @MainActor in "Expected loaded picks, got \(collector.bannerState)" }
    )

    let titles = collector.visiblePicks.map(\.episode.title)
    #expect(!titles.contains("Below Floor Pick"))
    #expect(titles.contains("Aligned Pick"))
  }

  // MARK: - Test: Post-Action Removal

  @Test("removePick drops the entry from visible picks")
  func postActionRemoval() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/remove.rss")!)
    await respondWithFeed(at: feedURL, title: "Remove", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(505))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected picks to land, got \(collector.visiblePicks.count)" }
    )

    let initialCount = collector.visiblePicks.count
    let removed = collector.visiblePicks[0].episode.mediaGUID
    collector.removePick(mediaGUID: removed)

    #expect(collector.visiblePicks.count == initialCount - 1)
    #expect(!collector.visiblePicks.contains { $0.episode.mediaGUID == removed })
  }

  // MARK: - Test: Typed-Search Overlay Replacement

  @Test("a new query replaces the typed-search overlay and cancels its work")
  func typedSearchOverlayReplacement() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let firstQueryFeed = FeedURL(URL(string: "https://example.com/first.rss")!)
    let secondQueryFeed = FeedURL(URL(string: "https://example.com/second.rss")!)

    // First query's RSS hangs so we can race a replacement against it.
    let firstSemaphore = await session.waitRespond(to: firstQueryFeed.rawValue, data: nil)
    await respondWithFeed(at: secondQueryFeed, title: "Second", episodes: 2)

    let firstSource = SearchRecommendationCollector.Source.search(query: "first")
    collector.setActiveSource(firstSource)
    collector.recordSourcePodcasts(
      source: firstSource,
      podcasts: [makeUnsavedRow(feedURL: firstQueryFeed, iTunesID: ITunesPodcastID(606))]
    )
    try await advanceStableSourceDebounce()

    // Wait for the in-flight RSS request to land at the session.
    try await Wait.until(
      { @MainActor in await self.session.requests.contains(firstQueryFeed.rawValue) },
      { @MainActor in "Expected first-query RSS request to be in flight" }
    )

    // Now replace the overlay with a new query.
    let secondSource = SearchRecommendationCollector.Source.search(query: "second")
    collector.setActiveSource(secondSource)
    collector.recordSourcePodcasts(
      source: secondSource,
      podcasts: [makeUnsavedRow(feedURL: secondQueryFeed, iTunesID: ITunesPodcastID(607))]
    )
    try await advanceStableSourceDebounce()

    // Release the first request so its task can finish (cancelled).
    firstSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        if case .loaded = collector.bannerState { return true }
        return false
      },
      { @MainActor in "Expected second query to load, got \(collector.bannerState)" }
    )

    let pickTitles = collector.visiblePicks.map(\.episode.title)
    #expect(pickTitles.contains(where: { $0.starts(with: "Second") }))
  }

  // MARK: - Test: Cross-Category Cache Reuse

  @Test("trending categories share the per-feed cache (one RSS request per feed)")
  func crossCategoryCacheReuse() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let sharedFeed = FeedURL(URL(string: "https://example.com/shared.rss")!)
    await respondWithFeed(at: sharedFeed, title: "Shared", episodes: 2)

    let row = makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(808))

    let comedy = SearchRecommendationCollector.Source.trending(genreID: 1303, title: "Comedy")
    let tech = SearchRecommendationCollector.Source.trending(genreID: 1318, title: "Technology")

    collector.setActiveSource(comedy)
    collector.recordSourcePodcasts(source: comedy, podcasts: [row])
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected comedy picks" }
    )

    // Switching to a different trending source that includes the same feed
    // URL should not trigger a second RSS request — the shared cache is hot.
    collector.setActiveSource(tech)
    collector.recordSourcePodcasts(source: tech, podcasts: [row])
    try await advanceStableSourceDebounce()

    // The tech source's picks should be immediately available because the
    // shared cache entry is already scored.
    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected tech picks via shared cache" }
    )

    let requests = await session.requests.filter { $0 == sharedFeed.rawValue }
    #expect(requests.count == 1)
  }

  // MARK: - Helpers

  private func makeUnsavedRow(
    feedURL: FeedURL,
    iTunesID: ITunesPodcastID
  ) -> PodcastWithEpisodeMetadata<ListedPodcast> {
    let unsaved = try! Create.unsavedPodcast(
      feedURL: feedURL,
      iTunesID: iTunesID,
      title: "Discovery Source",
      description: "Discovery Source"
    )
    return PodcastWithEpisodeMetadata(
      podcast: ListedPodcast(unsavedSearchResult: unsaved),
      episodeCount: 1,
      mostRecentEpisodeDate: Date()
    )
  }

  private func makeScriptedEmbeddable() -> ScriptedEmbeddable {
    // Signal episodes get three orthogonal vectors so the whitening transform
    // produces a non-degenerate centroid pointing in a measurable direction.
    // Discovery / candidate text defaults to the Signal-0 direction so its
    // similarity lands comfortably above the 0.5 floor; "Below Floor" text is
    // explicitly anti-aligned.
    ScriptedEmbeddable { text in
      if text.contains("Below Floor") { return [-1, 0, 0] }
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
  }

  private func primeEngine(embeddable: ScriptedEmbeddable) async throws {
    // Reset + register: the default test container already cached a
    // ContextualEmbedding around FakeEmbeddable, so we have to replace the
    // resolved instance, not just the underlying nlContextualEmbedding.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: embeddable) }
      .scope(.cached)

    // Whitening on tiny corpora (3 signal episodes, dim-3 vectors) produces
    // nan principal components and breaks similarity scoring. The Focused
    // mode skips the PCA strip entirely.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // We're driving similarityScore(forEmbedding:) directly from the
    // collector pipeline rather than topRecommendations, so only the cache
    // build matters; no candidate pool needed.
    let localEngine = Container.shared.recommendationEngine()
    localEngine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in localEngine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )
  }

  private func respondWithFeed(at feedURL: FeedURL, title: String, episodes: Int) async {
    let eps = (0..<episodes)
      .map { i in
        (
          "ep-\(i)-\(feedURL.absoluteString.hashValue)",
          // Use "Pick" so candidate titles don't collide with the scripted
          // embeddable's per-signal-episode rules.
          "\(title) Pick \(i)",
          Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(i * 86_400))
        )
      }
    await session.respond(
      to: feedURL.rawValue,
      data: rssXML(title: title, feedURL: feedURL, episodes: eps)
    )
  }

  private func advanceStableSourceDebounce() async throws {
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: SearchRecommendationCollector.stableSourceDebounce)
  }

  private func rssXML(
    title: String,
    feedURL: FeedURL,
    episodes: [(guid: String, title: String, pubDate: Date)]
  ) -> Data {
    let pubDateFormatter = DateFormatter()
    pubDateFormatter.locale = Locale(identifier: "en_US_POSIX")
    pubDateFormatter.timeZone = TimeZone(identifier: "GMT")
    pubDateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

    let items =
      episodes.map { entry -> String in
        """
        <item>
          <guid isPermaLink="false">\(entry.guid)</guid>
          <title>\(entry.title)</title>
          <pubDate>\(pubDateFormatter.string(from: entry.pubDate))</pubDate>
          <enclosure url="https://example.com/audio/\(entry.guid).mp3" type="audio/mpeg" length="0" />
          <description>\(entry.title) description</description>
        </item>
        """
      }
      .joined(separator: "\n")

    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
        <channel>
          <title>\(title)</title>
          <link>\(feedURL.absoluteString)</link>
          <description>\(title) description</description>
          <itunes:image href="https://example.com/image.png" />
          \(items)
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }
}
