// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector typed-search tests", .container)
@MainActor final class SearchRecommendationCollectorTypedSearchTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  // MARK: - Test: Typed-Search Overlay Replacement

  @Test("a new query replaces the typed-search overlay and cancels its work")
  func typedSearchOverlayReplacement() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let firstQueryFeed = FeedURL(URL(string: "https://example.com/first.rss")!)
    let secondQueryFeed = FeedURL(URL(string: "https://example.com/second.rss")!)

    // First query's RSS hangs so we can race a replacement against it.
    let firstSemaphore = await H.session.waitRespond(to: firstQueryFeed.rawValue, data: nil)
    await H.respondWithFeed(at: secondQueryFeed, title: "Second", episodes: 2)

    let firstSource = SearchRecommendationCollector.Source.search(query: "first")
    collector.setActiveSource(firstSource)
    collector.recordSourcePodcasts(
      source: firstSource,
      podcasts: [H.makeUnsavedRow(feedURL: firstQueryFeed, iTunesID: ITunesPodcastID(606))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(firstQueryFeed.rawValue) },
      { @MainActor in "Expected first-query RSS request to be in flight" }
    )

    let secondSource = SearchRecommendationCollector.Source.search(query: "second")
    collector.setActiveSource(secondSource)
    collector.recordSourcePodcasts(
      source: secondSource,
      podcasts: [H.makeUnsavedRow(feedURL: secondQueryFeed, iTunesID: ITunesPodcastID(607))]
    )
    try await H.advanceStableSourceDebounce()

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

  @Test("setActiveSource(.trending) after a typed search drops the overlay")
  func leavingTypedSearchReleasesOverlayAndTemporaryCache() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let queryFeed = FeedURL(URL(string: "https://example.com/typed-overlay.rss")!)
    await H.respondWithFeed(at: queryFeed, title: "Typed", episodes: 1)

    let typedSource = SearchRecommendationCollector.Source.search(query: "typed")
    collector.setActiveSource(typedSource)
    collector.recordSourcePodcasts(
      source: typedSource,
      podcasts: [H.makeUnsavedRow(feedURL: queryFeed, iTunesID: ITunesPodcastID(1901))]
    )
    try await H.advanceStableSourceDebounce()

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

    let trendingSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: nil, title: "Top")
    )
    collector.setActiveSource(trendingSource)

    #expect(collector.picks(for: typedSource).isEmpty)
    #expect(collector.bannerState(for: typedSource) == .hidden)
  }

  // MARK: - Test: Leaving Typed Search Cancels Pending Stable-Source Debouncer

  // If the user clears search before the 1 s debounce fires, overlay and
  // temporary are still empty — the pending debouncer is the only state
  // alive, and cleanup must cancel it or it'll resurrect the overlay.
  @Test("leaving typed search before the stable-source debounce fires cancels the pipeline")
  func leavingTypedSearchCancelsPendingStableSourceDebouncer() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let queryFeed = FeedURL(URL(string: "https://example.com/clear-before-debounce.rss")!)
    let trendingFeed = FeedURL(URL(string: "https://example.com/positive-sync-trending.rss")!)
    await H.respondWithFeed(at: queryFeed, title: "Cleared", episodes: 1)
    await H.respondWithFeed(at: trendingFeed, title: "Positive Sync", episodes: 1)

    let typedSource = SearchRecommendationCollector.Source.search(query: "cleared")
    collector.setActiveSource(typedSource)
    collector.recordSourcePodcasts(
      source: typedSource,
      podcasts: [H.makeUnsavedRow(feedURL: queryFeed, iTunesID: ITunesPodcastID(2001))]
    )

    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    // User leaves typed search — debouncer must be cancelled.
    let trendingSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: nil, title: "Top")
    )
    collector.setActiveSource(trendingSource)
    collector.recordSourcePodcasts(
      source: trendingSource,
      podcasts: [H.makeUnsavedRow(feedURL: trendingFeed, iTunesID: ITunesPodcastID(2002))]
    )

    // Trending debouncer fires at +1 s — past the typed-search wakeTime,
    // so a not-yet-cancelled typed debouncer would already have reconciled.
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(trendingFeed.rawValue) },
      { @MainActor in
        let r = await H.session.requests
        return "Expected trending RSS request to land; got \(r)"
      }
    )

    let requests = await H.session.requests
    #expect(
      !requests.contains(queryFeed.rawValue),
      "Stale typed-search debouncer fired after user left search; got \(requests)"
    )
    #expect(collector.picks(for: typedSource).isEmpty)
    #expect(collector.bannerState(for: typedSource) == .hidden)
  }

  // MARK: - Test: Typed-Search Debouncer Replacement Cancels Stale Query Pipeline

  @Test("a new typed-search query cancels the prior query's pending pipeline")
  func typedSearchDebouncerReplacementCancelsStaleQueryPipeline() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let fooFeed = FeedURL(URL(string: "https://example.com/foo-stale.rss")!)
    let barFeed = FeedURL(URL(string: "https://example.com/bar-current.rss")!)
    await H.respondWithFeed(at: fooFeed, title: "Foo", episodes: 1)
    await H.respondWithFeed(at: barFeed, title: "Bar", episodes: 1)

    let fooSource = SearchRecommendationCollector.Source.search(query: "foo")
    collector.setActiveSource(fooSource)
    collector.recordSourcePodcasts(
      source: fooSource,
      podcasts: [H.makeUnsavedRow(feedURL: fooFeed, iTunesID: ITunesPodcastID(1801))]
    )

    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    let barSource = SearchRecommendationCollector.Source.search(query: "bar")
    collector.setActiveSource(barSource)
    collector.recordSourcePodcasts(
      source: barSource,
      podcasts: [H.makeUnsavedRow(feedURL: barFeed, iTunesID: ITunesPodcastID(1802))]
    )

    // Cancelling foo's task doesn't unblock its FakeSleeper continuation —
    // wait for bar's sleep to also register so one advanceTime wakes both.
    // foo's body should then see Task.isCancelled and bail before its action.
    try await H.fakeSleeper.waitForSleepRequests(count: 2)
    await H.fakeSleeper.advanceTime(by: .seconds(1))

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

    let requests = await H.session.requests
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
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let sharedFeed = FeedURL(URL(string: "https://example.com/shared-typed.rss")!)
    let xml = H.rssXML(
      title: "Shared Typed",
      feedURL: sharedFeed,
      episodes: [
        ("shared-typed-ep", "Shared Typed Pick", Date(timeIntervalSince1970: 1_950_000_000))
      ]
    )
    let firstSemaphore = await H.session.waitRespond(to: sharedFeed.rawValue, data: xml)

    let row = H.makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(701))
    let firstSource = SearchRecommendationCollector.Source.search(query: "foo")
    collector.setActiveSource(firstSource)
    collector.recordSourcePodcasts(source: firstSource, podcasts: [row])
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(sharedFeed.rawValue) },
      { @MainActor in "Expected RSS request for shared feed to be in flight" }
    )

    let secondSource = SearchRecommendationCollector.Source.search(query: "fooz")
    collector.setActiveSource(secondSource)
    collector.recordSourcePodcasts(source: secondSource, podcasts: [row])
    try await H.advanceStableSourceDebounce()

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

  // MARK: - Test: Typed-Search Query Change Does Not Cancel Trending Work

  @Test("typed-search query change does not cancel work owned by a trending source")
  func typedSearchQueryChangeDoesNotCancelTrendingWork() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    // Lands in `permanent` via trending, re-referenced (not owned) by "f".
    let sharedFeed = FeedURL(URL(string: "https://example.com/cross-cache.rss")!)
    let sharedSemaphore = await H.session.waitRespond(
      to: sharedFeed.rawValue,
      data: H.rssXML(
        title: "Cross Cache",
        feedURL: sharedFeed,
        episodes: [
          ("cross-cache-ep", "Cross Pick", Date(timeIntervalSince1970: 1_960_000_000))
        ]
      )
    )

    let gOnlyFeed = FeedURL(URL(string: "https://example.com/g-only.rss")!)
    await H.respondWithFeed(at: gOnlyFeed, title: "G Only", episodes: 1)

    let trending = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(trending)
    collector.recordSourcePodcasts(
      source: trending,
      podcasts: [H.makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(1201))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(sharedFeed.rawValue) },
      { @MainActor in "Expected trending RSS request to be in flight" }
    )

    // "f" reuses the trending entry without taking ownership.
    let fSource = SearchRecommendationCollector.Source.search(query: "f")
    collector.setActiveSource(fSource)
    collector.recordSourcePodcasts(
      source: fSource,
      podcasts: [H.makeUnsavedRow(feedURL: sharedFeed, iTunesID: ITunesPodcastID(1201))]
    )
    try await H.advanceStableSourceDebounce()

    // "g" replaces the overlay; must not cancel trending-owned work.
    let gSource = SearchRecommendationCollector.Source.search(query: "g")
    collector.setActiveSource(gSource)
    collector.recordSourcePodcasts(
      source: gSource,
      podcasts: [H.makeUnsavedRow(feedURL: gOnlyFeed, iTunesID: ITunesPodcastID(1202))]
    )
    try await H.advanceStableSourceDebounce()

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

    let cancelled = await H.session.cancelledRequests
    #expect(!cancelled.contains(sharedFeed.rawValue))
    #expect(!collector.picks(for: trending).isEmpty)
  }
}
