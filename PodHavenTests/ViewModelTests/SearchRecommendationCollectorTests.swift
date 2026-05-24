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
    collector.removePick(feedURL: feedURL, mediaGUID: removed)

    #expect(collector.visiblePicks.count == initialCount - 1)
    #expect(!collector.visiblePicks.contains { $0.episode.mediaGUID == removed })
  }

  // MARK: - Test: removePick Works When Parsed Feed URL Differs From Entry Key

  @Test("removePick removes a pick whose parsed feed URL differs from the entry key")
  func removePickHandlesAlternateFeedURL() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let requestedURL = FeedURL(URL(string: "https://example.com/iTunes-source.rss")!)
    let parsedSelfURL = FeedURL(URL(string: "https://example.com/canonical-self.rss")!)

    // Custom RSS where atom:link rel="self" points at a *different* URL than
    // the one we downloaded. PodcastFeed will set the unsavedPodcast's feedURL
    // from atom:link, so the rendered ListedEpisode.feedURL is the canonical
    // URL — but the collector's cache key is still the requested URL.
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" \
      xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>Canonical Differs</title>
          <link>\(requestedURL.absoluteString)</link>
          <description>Canonical Differs description</description>
          <itunes:image href="https://example.com/image.png" />
          <atom:link rel="self" href="\(parsedSelfURL.absoluteString)" />
          <item>
            <guid isPermaLink="false">canon-pick-1</guid>
            <title>Canonical Pick</title>
            <pubDate>Mon, 14 Nov 2023 22:13:20 +0000</pubDate>
            <enclosure url="https://example.com/audio/canon-pick-1.mp3" type="audio/mpeg" length="0" />
            <description>Canonical Pick description</description>
          </item>
        </channel>
      </rss>
      """
    await session.respond(to: requestedURL.rawValue, data: Data(xml.utf8))

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: requestedURL, iTunesID: ITunesPodcastID(1901))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count >= 1 },
      { @MainActor in "Expected pick to land, got \(collector.visiblePicks.count)" }
    )

    let pick = collector.visiblePicks[0]
    // Sanity: the parsed feedURL must not equal the requested URL, otherwise
    // this test doesn't exercise the mismatch we care about.
    #expect(
      pick.episode.feedURL == parsedSelfURL,
      "Test setup invariant: parsed feed URL must differ from requested URL"
    )

    let listed = ListedEpisode(pick.episode)
    collector.removePick(feedURL: listed.feedURL, mediaGUID: listed.mediaGUID)

    #expect(
      collector.visiblePicks.isEmpty,
      "Expected pick to be removed even when its feedURL differs from the cache key"
    )
  }

  // MARK: - Test: saveEpisodeInCache Through ManagingEpisodes Dispatch

  // EpisodeContextMenuViewModifier<ViewModel: ManagingEpisodes> calls
  // `viewModel.saveEpisodeInCache(...)`. If the method lives only in the
  // ManagingEpisodes extension (not in the protocol itself), static dispatch
  // through the generic constraint picks the extension default and any
  // conforming-type override is bypassed. Hoisting saveEpisodeInCache into the
  // protocol makes dispatch dynamic so per-type overrides actually run.
  @Test("saveEpisodeInCache dispatched via ManagingEpisodes constraint calls the override")
  func saveEpisodeInCacheThroughProtocolDispatchCallsOverride() throws {
    let unsaved = try Create.unsavedPodcast(title: "Dispatch Source")
    let episode = try Create.unsavedEpisode(title: "Dispatch Pick")
    let payload = UnsavedPodcastEpisode(unsavedPodcast: unsaved, unsavedEpisode: episode)
    let listed = ListedEpisode(payload)

    let tracker = TrackingManagingEpisodes()
    Self.dispatchSaveEpisodeInCacheViaProtocol(viewModel: tracker, episode: listed)

    #expect(
      tracker.saveCalledOnSelf,
      "Expected the ManagingEpisodes-override to be reached via dynamic dispatch"
    )
  }

  private static func dispatchSaveEpisodeInCacheViaProtocol<V: ManagingEpisodes>(
    viewModel: V,
    episode: V.EpisodeType
  ) {
    viewModel.saveEpisodeInCache(episode)
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

  // MARK: - Test: Leaving Typed Search Releases Overlay-Owned Cache

  // SearchView leaves typed search via `setActiveSource(.trending)` whenever
  // the user clears the search bar. Without overlay cleanup on that
  // transition, the typed-search overlay (and every `temporary` entry it
  // created) would linger until tearDown, growing the per-tab-visit memory
  // footprint by one slot per typed query.
  @Test("setActiveSource(.trending) after a typed search drops the overlay")
  func leavingTypedSearchReleasesOverlayAndTemporaryCache() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let queryFeed = FeedURL(URL(string: "https://example.com/typed-overlay.rss")!)
    await respondWithFeed(at: queryFeed, title: "Typed", episodes: 1)

    let typedSource = SearchRecommendationCollector.Source.search(query: "typed")
    collector.setActiveSource(typedSource)
    collector.recordSourcePodcasts(
      source: typedSource,
      podcasts: [makeUnsavedRow(feedURL: queryFeed, iTunesID: ITunesPodcastID(1901))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState(for: typedSource), count > 0 {
          return true
        }
        return false
      },
      { @MainActor in
        "Expected typed picks to land; got \(collector.bannerState(for: typedSource))"
      }
    )

    let trendingSource = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(trendingSource)

    #expect(collector.picks(for: typedSource).isEmpty)
    #expect(collector.bannerState(for: typedSource) == .hidden)
  }

  // MARK: - Test: Leaving Typed Search Cancels Pending Stable-Source Debouncer

  // When the user clears search before the 1 s stable-source debounce fires,
  // overlay and temporary are still empty — the pending typedSearchDebouncer
  // is the only typed-search state alive. Cleanup must cancel it anyway, or
  // the debounce fires after the user has left typed search and reconcile
  // resurrects the overlay + kicks an RSS request for the abandoned query.
  @Test("leaving typed search before the stable-source debounce fires cancels the pipeline")
  func leavingTypedSearchCancelsPendingStableSourceDebouncer() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let queryFeed = FeedURL(URL(string: "https://example.com/clear-before-debounce.rss")!)
    await respondWithFeed(at: queryFeed, title: "Cleared", episodes: 1)

    let typedSource = SearchRecommendationCollector.Source.search(query: "cleared")
    collector.setActiveSource(typedSource)
    collector.recordSourcePodcasts(
      source: typedSource,
      podcasts: [makeUnsavedRow(feedURL: queryFeed, iTunesID: ITunesPodcastID(2001))]
    )

    // The 1 s stable-source debouncer is now pending. Overlay and temporary
    // are still empty — the debouncer hasn't fired its reconcile yet.
    try await fakeSleeper.waitForSleepRequests(count: 1)

    // User clears the search bar; SearchView's empty branch flips activeSource
    // back to .trending and the collector's setActiveSource hook must cancel
    // the pending typed-search work.
    let trendingSource = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(trendingSource)

    // Advance past the debounce. With the fix, the cancelled task body bails
    // before calling reconcileAndIngest; without it, the action fires and
    // queryFeed reaches RSS fan-out.
    await fakeSleeper.advanceTime(by: .seconds(1))

    // Give the (would-be) drain a generous window to surface the request.
    do {
      try await Wait.until(
        maxAttempts: 100,
        { @MainActor in await self.session.requests.contains(queryFeed.rawValue) },
        { @MainActor in "settle" }
      )
      Issue.record(
        "Stale typed-search debouncer fired after user left search — \(queryFeed.rawValue) was requested"
      )
    } catch {
      // Wait.until timed out without ever seeing the request — fix is working.
    }

    #expect(collector.picks(for: typedSource).isEmpty)
    #expect(collector.bannerState(for: typedSource) == .hidden)
  }

  // MARK: - Test: Typed-Search Debouncer Replacement Cancels Stale Query Pipeline

  // Per-query debouncers let a stale typed-search query (`foo`) fire its
  // stable-source action after a newer query (`bar`) has already taken over.
  // With a single shared typed-search debouncer, recording `bar` cancels the
  // pending `foo` action, so `foo`'s feed never reaches RSS fan-out.
  @Test("a new typed-search query cancels the prior query's pending pipeline")
  func typedSearchDebouncerReplacementCancelsStaleQueryPipeline() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let fooFeed = FeedURL(URL(string: "https://example.com/foo-stale.rss")!)
    let barFeed = FeedURL(URL(string: "https://example.com/bar-current.rss")!)
    await respondWithFeed(at: fooFeed, title: "Foo", episodes: 1)
    await respondWithFeed(at: barFeed, title: "Bar", episodes: 1)

    let fooSource = SearchRecommendationCollector.Source.search(query: "foo")
    collector.setActiveSource(fooSource)
    collector.recordSourcePodcasts(
      source: fooSource,
      podcasts: [makeUnsavedRow(feedURL: fooFeed, iTunesID: ITunesPodcastID(1801))]
    )

    // foo's stable-source debouncer is pending. Do NOT advance time yet.
    try await fakeSleeper.waitForSleepRequests(count: 1)

    let barSource = SearchRecommendationCollector.Source.search(query: "bar")
    collector.setActiveSource(barSource)
    collector.recordSourcePodcasts(
      source: barSource,
      podcasts: [makeUnsavedRow(feedURL: barFeed, iTunesID: ITunesPodcastID(1802))]
    )

    // Cancelling foo's task doesn't unblock its FakeSleeper continuation —
    // it stays parked in sleepRequests until time advances past its wakeTime.
    // Wait for bar's sleep to also register so a single advanceTime call wakes
    // both. With the fix, foo's task body then sees `Task.isCancelled` after
    // the sleep returns and bails before calling its action; with the bug,
    // foo's reconcile fires and fooFeed reaches the RSS fan-out.
    try await fakeSleeper.waitForSleepRequests(count: 2)
    await fakeSleeper.advanceTime(by: .seconds(1))

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState(for: barSource), count > 0 {
          return true
        }
        return false
      },
      { @MainActor in
        "Expected bar query to load picks; got \(collector.bannerState(for: barSource))"
      }
    )

    let requests = await session.requests
    #expect(
      !requests.contains(fooFeed.rawValue),
      "Stale foo query should not have reached RSS fan-out; got requests \(requests)"
    )
    #expect(requests.contains(barFeed.rawValue))
  }

  // MARK: - Test: Typed-Search Shared FeedURL Across Queries (Regression)

  @Test("typed-search query change keeps in-flight entry when feedURL re-appears")
  func typedSearchSharedFeedURLAcrossQueries() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let sharedFeed = FeedURL(URL(string: "https://example.com/shared-typed.rss")!)
    let xml = rssXML(
      title: "Shared Typed",
      feedURL: sharedFeed,
      episodes: [
        ("shared-typed-ep", "Shared Typed Pick", Date(timeIntervalSince1970: 1_950_000_000))
      ]
    )
    let firstSemaphore = await session.waitRespond(to: sharedFeed.rawValue, data: xml)

    let row = makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(701))
    let firstSource = SearchRecommendationCollector.Source.search(query: "foo")
    collector.setActiveSource(firstSource)
    collector.recordSourcePodcasts(source: firstSource, podcasts: [row])
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await self.session.requests.contains(sharedFeed.rawValue) },
      { @MainActor in "Expected RSS request for shared feed to be in flight" }
    )

    let secondSource = SearchRecommendationCollector.Source.search(query: "fooz")
    collector.setActiveSource(secondSource)
    collector.recordSourcePodcasts(source: secondSource, podcasts: [row])
    try await advanceStableSourceDebounce()

    firstSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState(for: secondSource), count > 0 {
          return true
        }
        return false
      },
      { @MainActor in
        """
        Expected second query to load picks for shared feed; \
        got \(collector.bannerState(for: secondSource))
        """
      }
    )
    #expect(!collector.picks(for: secondSource).isEmpty)
  }

  // MARK: - Test: Teardown Clears Caches

  @Test("tearDown clears caches and the drain task")
  func tearDownClearsCaches() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown.rss")!)
    await respondWithFeed(at: feedURL, title: "Teardown", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(801))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState, count > 0 { return true }
        return false
      },
      { @MainActor in "Expected picks to land before teardown, got \(collector.bannerState)" }
    )

    collector.tearDown()

    #expect(collector.picks(for: source).isEmpty)
    #expect(collector.bannerState(for: source) == .hidden)
    #expect(collector.visiblePicks.isEmpty)
    #expect(collector.bannerState == .hidden)
  }

  // MARK: - Test: Teardown Cancels In-Flight Download

  @Test("tearDown cancels an in-flight RSS download")
  func tearDownCancelsInFlightDownload() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-inflight.rss")!)
    // Hold the RSS response so processFeedURL stays suspended on
    // downloadFinished. tearDown must cancel the underlying DownloadTask,
    // which in turn cancels this handler's wait.
    let semaphore = await session.waitRespond(
      to: feedURL.rawValue,
      data: rssXML(
        title: "Teardown InFlight",
        feedURL: feedURL,
        episodes: [
          ("teardown-inflight-ep", "Pick", Date(timeIntervalSince1970: 1_950_000_000))
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1102))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await self.session.requests.contains(feedURL.rawValue) },
      { @MainActor in "Expected RSS request to be in flight before teardown" }
    )

    collector.tearDown()

    try await Wait.until(
      { @MainActor in await self.session.cancelledRequests.contains(feedURL.rawValue) },
      { @MainActor in
        let cancelled = await self.session.cancelledRequests
        return "Expected RSS request to be cancelled after teardown; got \(cancelled)"
      }
    )

    // Releasing the held response is a no-op now — cancellation took hold
    // before the response could deliver.
    semaphore.signal()

    #expect(collector.visiblePicks.isEmpty)
    #expect(collector.bannerState == .hidden)
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: Teardown Cancels Pending Debouncer Action

  @Test("tearDown cancels a pending stable-source debouncer action")
  func tearDownCancelsPendingDebouncerAction() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-debouncer.rss")!)
    await respondWithFeed(at: feedURL, title: "Teardown Debouncer", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1701))]
    )

    // Wait for the debouncer's 1 s sleep to be registered, but DO NOT advance
    // time yet — the reconcile / RSS work is gated behind that sleep.
    try await fakeSleeper.waitForSleepRequests(count: 1)

    collector.tearDown()

    // Past tearDown, advancing time must NOT cause the debouncer action to
    // fire. Without cancelling the debouncer's underlying Task, advanceTime
    // resumes it and reconcileAndIngest runs after teardown.
    await fakeSleeper.advanceTime(by: .seconds(2))

    // Give a generous settle window. If the stale debouncer were still alive,
    // reconcileAndIngest would repopulate caches and the drain task would
    // download the RSS — which we'd observe in session.requests.
    do {
      try await Wait.until(
        maxAttempts: 100,
        { @MainActor in await self.session.requests.contains(feedURL.rawValue) },
        { @MainActor in "settle" }
      )
      Issue.record(
        "Stale debouncer fired after tearDown — \(feedURL.rawValue) was requested"
      )
    } catch {
      // Wait.until timed out without ever seeing the request — fix is working.
    }

    #expect(collector.bannerState == .hidden)
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: Banner Hides When Engine Pre-Rebuilt To Nil

  @Test("banner hides when engine rebuilt to no context before collector subscribed")
  func bannerHidesWhenEnginePreRebuiltToNil() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()

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
    await respondWithFeed(at: feedURL, title: "Pre Rebuilt Nil", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1602))]
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

  // MARK: - Test: picks(for:) Is Independent Of activeSource

  @Test("picks(for:) returns picks for the requested source regardless of activeSource")
  func picksForSourceIndependentOfActiveSource() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    let comedyFeed = FeedURL(URL(string: "https://example.com/independent-comedy.rss")!)
    await respondWithFeed(at: comedyFeed, title: "Comedy", episodes: 2)

    let comedy = SearchRecommendationCollector.Source.trending(genreID: 1303, title: "Comedy")
    let tech = SearchRecommendationCollector.Source.trending(genreID: 1318, title: "Technology")

    collector.setActiveSource(comedy)
    collector.recordSourcePodcasts(
      source: comedy,
      podcasts: [makeUnsavedRow(feedURL: comedyFeed, iTunesID: ITunesPodcastID(901))]
    )
    try await advanceStableSourceDebounce()

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

  // MARK: - Test: Cold Engine Defers Pipeline Until Hot

  @Test("recording before engine is hot yields picks once the engine warms")
  func recordingBeforeEngineHotEventuallyYieldsPicks() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()

    // Set up only the embedding factory. Do NOT seed signal episodes or
    // start the engine yet, so `hasScoringContext` stays false until we
    // explicitly prime it partway through the test.
    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let feedURL = FeedURL(URL(string: "https://example.com/cold-engine.rss")!)
    await respondWithFeed(at: feedURL, title: "Cold Engine", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1001))]
    )
    try await advanceStableSourceDebounce()

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
    let scripted = makeScriptedEmbeddable()

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
    await respondWithFeed(at: feedURL, title: "No Scoring", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1601))]
    )
    try await advanceStableSourceDebounce()

    // Wait for the reconcile to apply: feedURL lands in the source index with
    // a pending entry, banner enters .loading. Past this point the drain task
    // is blocked inside awaitScoringContext.
    try await Wait.until(
      { @MainActor in collector.bannerState == .loading },
      { @MainActor in
        "Expected banner to enter .loading after reconcile; got \(collector.bannerState)"
      }
    )

    // Advance time once, well beyond the engine's 400 ms cacheRebuild debounce.
    // That fires buildContext (returns nil) and bumps scoringRevision. With
    // the fix, awaitScoringContext returns and the banner transitions to
    // .hidden; without it, the banner stays .loading forever.
    await fakeSleeper.advanceTime(by: .seconds(5))
    try await Wait.until(
      { @MainActor in collector.bannerState == .hidden },
      { @MainActor in
        "Expected banner to hide once scoring is determined unavailable, got \(collector.bannerState)"
      }
    )
  }

  // MARK: - Test: Typed-Search Query Change Does Not Cancel Trending Work

  @Test("typed-search query change does not cancel work owned by a trending source")
  func typedSearchQueryChangeDoesNotCancelTrendingWork() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = makeScriptedEmbeddable()
    try await primeEngine(embeddable: scripted)

    // Shared feed: lands in `permanent` via the trending source, then is
    // re-referenced (but not owned) by typed-search "f".
    let sharedFeed = FeedURL(URL(string: "https://example.com/cross-cache.rss")!)
    let sharedSemaphore = await session.waitRespond(
      to: sharedFeed.rawValue,
      data: rssXML(
        title: "Cross Cache",
        feedURL: sharedFeed,
        episodes: [
          ("cross-cache-ep", "Cross Pick", Date(timeIntervalSince1970: 1_960_000_000))
        ]
      )
    )

    // Distinct feed so the "g" ranking is non-empty.
    let gOnlyFeed = FeedURL(URL(string: "https://example.com/g-only.rss")!)
    await respondWithFeed(at: gOnlyFeed, title: "G Only", episodes: 1)

    let trending = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(trending)
    collector.recordSourcePodcasts(
      source: trending,
      podcasts: [makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(1201))]
    )
    try await advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await self.session.requests.contains(sharedFeed.rawValue) },
      { @MainActor in "Expected trending RSS request to be in flight" }
    )

    // Typed-search "f" references the same feed — reuses the trending entry
    // without taking ownership.
    let fSource = SearchRecommendationCollector.Source.search(query: "f")
    collector.setActiveSource(fSource)
    collector.recordSourcePodcasts(
      source: fSource,
      podcasts: [makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(1201))]
    )
    try await advanceStableSourceDebounce()

    // Typed-search "g" replaces the overlay with a different feed. Must NOT
    // cancel the trending-owned in-flight work for sharedFeed.
    let gSource = SearchRecommendationCollector.Source.search(query: "g")
    collector.setActiveSource(gSource)
    collector.recordSourcePodcasts(
      source: gSource,
      podcasts: [makeUnsavedRow(feedURL: gOnlyFeed, iTunesID: ITunesPodcastID(1202))]
    )
    try await advanceStableSourceDebounce()

    sharedSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        if case .loaded(let count) = collector.bannerState(for: trending), count > 0 {
          return true
        }
        return false
      },
      { @MainActor in
        "Expected trending picks after typed-search churn; got \(collector.bannerState(for: trending))"
      }
    )

    let cancelled = await session.cancelledRequests
    #expect(!cancelled.contains(sharedFeed.rawValue))
    #expect(!collector.picks(for: trending).isEmpty)
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

// Minimal ManagingEpisodes conformer used by the dispatch test. The body of
// saveEpisodeInCache flips a flag so the test can detect whether dynamic
// dispatch reached the override or fell through to the protocol-extension
// default (which would never touch this flag).
@MainActor
private final class TrackingManagingEpisodes: ManagingEpisodes {
  typealias EpisodeType = ListedEpisode

  var saveCalledOnSelf = false

  func saveEpisodeInCache(_ episode: ListedEpisode) { saveCalledOnSelf = true }

  func isEpisodePlaying(_ episode: ListedEpisode) -> Bool { false }
  func isEpisodeAtBottomOfQueue(_ episode: ListedEpisode) -> Bool { false }
  func canClearCache(_ episode: ListedEpisode) -> Bool { false }
  func playEpisode(_ episode: ListedEpisode) {}
  func pauseEpisode(_ episode: ListedEpisode) {}
  func queueEpisodeOnTop(_ episode: ListedEpisode, swipeAction: Bool) {}
  func queueEpisodeAtBottom(_ episode: ListedEpisode, swipeAction: Bool) {}
  func removeEpisodeFromQueue(_ episode: ListedEpisode) {}
  func cacheEpisode(_ episode: ListedEpisode) {}
  func uncacheEpisode(_ episode: ListedEpisode) {}
  func rateEpisode(_ episode: ListedEpisode, rating: EpisodeRating?) {}
  func markEpisodeFinished(_ episode: ListedEpisode) {}
  func addTag(_ tagID: PodHaven.Tag.ID, to episode: ListedEpisode) {}
  func removeTag(_ tagID: PodHaven.Tag.ID, from episode: ListedEpisode) {}
}
