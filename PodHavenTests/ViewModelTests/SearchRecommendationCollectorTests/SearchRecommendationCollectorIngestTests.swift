// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector ingest tests", .container)
@MainActor final class SearchRecommendationCollectorIngestTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  @DynamicInjected(\.repo) private var repo

  // MARK: - Test: Happy Path

  @Test("recordSourcePodcasts → picks land after stable-source debounce")
  func happyPath() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/discovery.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Discovery", episodes: 3)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(101))]
    )

    try await H.advanceStableSourceDebounce()

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

  @Test("stable-source debounce holds RSS fan-out until the debounce elapses")
  func stableSourceDebounce() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/slow.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Slow", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(202))]
    )

    try await H.fakeSleeper.waitForSleepRequests(count: 1)
    let earlyRequests = await H.session.requests
    #expect(!earlyRequests.contains(feedURL.rawValue))

    await H.fakeSleeper.advanceTime(by: SearchRecommendationCollector.stableSourceDebounce)

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(feedURL.rawValue) },
      { @MainActor in
        let r = await H.session.requests
        return "Expected RSS request for \(feedURL.rawValue); got \(r)"
      }
    )
  }

  // MARK: - Test: iTunes-ID Reconciliation Deduplicates Canonical Feed URL

  // Two iTunes rows with different slot URLs but the same iTunesID both
  // bridge to the same saved-unsubscribed row, collapsing to one canonical
  // feed URL. Without dedupe, `reconciledFeedURLs` carries the canonical
  // URL twice and `picks(for:)` appends `scoredEpisodes` once per copy,
  // doubling the visible picks and the banner count.
  @Test("two iTunes rows reconciling to the same saved podcast yield one pick each")
  func iTunesIDReconciliationDeduplicatesCanonicalFeedURL() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let canonicalFeedURL = FeedURL(URL(string: "https://example.com/dedupe-canonical.rss")!)
    let slotA = FeedURL(URL(string: "https://example.com/dedupe-slot-a.rss")!)
    let slotB = FeedURL(URL(string: "https://example.com/dedupe-slot-b.rss")!)
    let iTunesID = ITunesPodcastID(4101)

    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: canonicalFeedURL,
          iTunesID: iTunesID,
          title: "Dedupe Canonical",
          subscriptionDate: nil
        ),
        unsavedEpisodes: []
      )
    )

    await H.respondWithFeed(at: canonicalFeedURL, title: "Dedupe", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [
        H.makeUnsavedRow(feedURL: slotA, iTunesID: iTunesID),
        H.makeUnsavedRow(feedURL: slotB, iTunesID: iTunesID),
      ]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected loaded picks, got \(collector.bannerState)" }
    )

    #expect(
      collector.visiblePicks.count == 1,
      """
      Expected one pick from the deduped canonical feed; \
      got \(collector.visiblePicks.count) picks
      """
    )
    #expect(collector.bannerState == .loaded(count: 1))
  }

  // MARK: - Test: Subscribed Exclusion via iTunesID Reconciliation

  @Test("subscribed podcast is excluded after DB reconciliation by iTunes ID")
  func subscribedExclusionByITunesID() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let canonicalFeedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let searchFeedURL = FeedURL(URL(string: "https://example.com/search-row.rss")!)
    let iTunesID = ITunesPodcastID(909)

    // Different feedURL but matching iTunesID — must reconcile by iTunes ID.
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
    await H.respondWithFeed(at: alsoUnsubscribedFeedURL, title: "Pass-Through", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [
        H.makeUnsavedRow(feedURL: searchFeedURL, iTunesID: iTunesID),
        H.makeUnsavedRow(feedURL: alsoUnsubscribedFeedURL, iTunesID: ITunesPodcastID(910)),
      ]
    )

    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded = collector.bannerState { return true }
        return false
      },
      { @MainActor in "Expected at least one pick, got \(collector.bannerState)" }
    )

    let requests = await H.session.requests
    #expect(!requests.contains(canonicalFeedURL.rawValue))
    #expect(!requests.contains(searchFeedURL.rawValue))
    #expect(requests.contains(alsoUnsubscribedFeedURL.rawValue))
  }

  // MARK: - Test: Candidate Gate Filters Rated Episodes

  @Test("candidate gate drops episodes matching a rated DB row")
  func candidateGateFiltersRatedEpisodes() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/gated.rss")!)

    // Existing rated row matching one RSS GUID — must be dropped by the gate.
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

    #expect(unsavedSeries.podcast.subscriptionDate == nil)

    await H.session.respond(
      to: feedURL.rawValue,
      data: H.rssXML(
        title: "Gated",
        feedURL: feedURL,
        episodes: [
          ("gated-ep-rated", "Already Rated", Date(timeIntervalSince1970: 1_700_000_000)),
          ("gated-ep-new", "Fresh Episode", Date(timeIntervalSince1970: 1_800_000_000)),
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(303))]
    )

    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected at least one pick, got \(collector.bannerState)" }
    )

    let guids = collector.visiblePicks.map(\.episode.mediaGUID.guid.rawValue)
    #expect(!guids.contains("gated-ep-rated"))
    #expect(guids.contains("gated-ep-new"))
  }

  // MARK: - Test: Candidate Gate Keeps Cached Episodes

  // Caching doesn't change candidacy — an episode the user cached still shows in
  // topRecommendations / UpNext — so the discovery gate must NOT drop it. The
  // gate mirrors `Episode.candidate`, which ignores cache state.
  @Test("candidate gate keeps episodes matching a cached DB row")
  func candidateGateKeepsCachedEpisodes() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/gated-cache.rss")!)

    // Existing cached row matching one RSS GUID — must be dropped by the gate.
    let cachedGUID = GUID("gated-ep-cached")
    let unsavedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: ITunesPodcastID(404),
          title: "Gated Cache",
          subscriptionDate: nil
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: cachedGUID,
            title: "Already Cached",
            cachedFilename: "cached.mp3"
          )
        ]
      )
    )

    #expect(unsavedSeries.podcast.subscriptionDate == nil)

    await H.session.respond(
      to: feedURL.rawValue,
      data: H.rssXML(
        title: "Gated Cache",
        feedURL: feedURL,
        episodes: [
          ("gated-ep-cached", "Already Cached", Date(timeIntervalSince1970: 1_700_000_000)),
          ("gated-ep-new", "Fresh Episode", Date(timeIntervalSince1970: 1_800_000_000)),
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(404))]
    )

    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected at least one pick, got \(collector.bannerState)" }
    )

    let guids = collector.picks(for: source).map(\.episode.mediaGUID.guid.rawValue)
    #expect(guids.contains("gated-ep-cached"))
    #expect(guids.contains("gated-ep-new"))
  }

  // MARK: - Test: Score Ordering

  @Test("score floor filters episodes whose similarity is too low")
  func scoreOrdering() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/order.rss")!)
    await H.session.respond(
      to: feedURL.rawValue,
      data: H.rssXML(
        title: "Order",
        feedURL: feedURL,
        episodes: [
          ("ord-default", "Aligned Pick", Date(timeIntervalSince1970: 1_900_000_000)),
          ("ord-floor", "Below Floor Pick", Date(timeIntervalSince1970: 2_000_000_000)),
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(404))]
    )

    try await H.advanceStableSourceDebounce()

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

  // MARK: - Test: picks(for:) Is Independent Of activeSource

  @Test("picks(for:) returns picks for the requested source regardless of activeSource")
  func picksForSourceIndependentOfActiveSource() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let comedyFeed = FeedURL(URL(string: "https://example.com/independent-comedy.rss")!)
    await H.respondWithFeed(at: comedyFeed, title: "Comedy", episodes: 2)

    let comedy = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    let tech = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1318, title: "Technology")
    )

    collector.setActiveSource(comedy)
    collector.recordSourcePodcasts(
      source: comedy,
      podcasts: [H.makeUnsavedRow(feedURL: comedyFeed, iTunesID: ITunesPodcastID(901))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in !collector.picks(for: comedy).isEmpty },
      { @MainActor in "Expected comedy picks to land" }
    )

    collector.setActiveSource(tech)

    #expect(!collector.picks(for: comedy).isEmpty)
    #expect(
      collector.bannerState(for: comedy) == .loaded(count: collector.picks(for: comedy).count)
    )
    #expect(collector.picks(for: tech).isEmpty)
    #expect(collector.bannerState(for: tech) == .hidden)
    #expect(collector.visiblePicks.isEmpty)
  }

  // MARK: - Test: Cross-Category Cache Reuse

  @Test("trending categories share the per-feed cache (one RSS request per feed)")
  func crossCategoryCacheReuse() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let sharedFeed = FeedURL(URL(string: "https://example.com/shared.rss")!)
    await H.respondWithFeed(at: sharedFeed, title: "Shared", episodes: 2)

    let row = H.makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(808))

    let comedy = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    let tech = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1318, title: "Technology")
    )

    collector.setActiveSource(comedy)
    collector.recordSourcePodcasts(source: comedy, podcasts: [row])
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected comedy picks" }
    )

    collector.setActiveSource(tech)
    collector.recordSourcePodcasts(source: tech, podcasts: [row])
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected tech picks via shared cache" }
    )

    let requests = await H.session.requests.filter { $0 == sharedFeed.rawValue }
    #expect(requests.count == 1)
  }

  // MARK: - Test: Failed Feeds Are Not Re-Fetched On Re-Record

  // A feed whose RSS fetch fails settles as terminal `.failed`. Re-recording
  // the same source — as observation re-emits routinely do — must not re-queue
  // it; only genuinely new feeds should fetch. The fence feed fetching proves
  // the second drain pass ran, so the failed feed's single request count is a
  // deterministic assertion rather than a timing race.
  @Test("a failed feed is not re-fetched when the source is re-recorded")
  func failedFeedNotRefetchedOnReRecord() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let failingFeed = FeedURL(URL(string: "https://example.com/failing.rss")!)
    await H.session.respond(to: failingFeed.rawValue, error: URLError(.timedOut))

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    let failingRow = H.makeUnsavedRow(feedURL: failingFeed, iTunesID: ITunesPodcastID(501))

    collector.setActiveSource(source)
    collector.recordSourcePodcasts(source: source, podcasts: [failingRow])
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(failingFeed.rawValue) },
      { @MainActor in "Expected the failing feed to be fetched once" }
    )
    // The fetch error settles the entry to .failed: feed URLs are present, no
    // picks landed, and nothing is in flight, so the banner is hidden.
    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in
        "Expected the failed feed to settle to a hidden banner, got \(collector.bannerState)"
      }
    )

    let fenceFeed = FeedURL(URL(string: "https://example.com/fence.rss")!)
    await H.respondWithFeed(at: fenceFeed, title: "Fence", episodes: 1)
    let fenceRow = H.makeUnsavedRow(feedURL: fenceFeed, iTunesID: ITunesPodcastID(502))

    collector.recordSourcePodcasts(source: source, podcasts: [failingRow, fenceRow])
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(fenceFeed.rawValue) },
      { @MainActor in "Expected the fence feed to be fetched on re-record" }
    )

    let failingRequests = await H.session.requests.filter { $0 == failingFeed.rawValue }
    #expect(
      failingRequests.count == 1,
      "Expected the failed feed to be fetched once; got \(failingRequests.count)"
    )
  }
}
