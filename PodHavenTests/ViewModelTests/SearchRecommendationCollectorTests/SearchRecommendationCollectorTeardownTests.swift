// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector teardown tests", .container)
@MainActor final class SearchRecommendationCollectorTeardownTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  // MARK: - Test: Teardown Clears Caches

  @Test("tearDown clears caches and the drain task")
  func tearDownClearsCaches() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Teardown", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(801))]
    )
    try await H.advanceStableSourceDebounce()

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
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-inflight.rss")!)
    // Hold the response so processFeedURL stays suspended on downloadFinished;
    // tearDown must cancel the DownloadTask, which cancels this handler.
    let semaphore = await H.session.waitRespond(
      to: feedURL.rawValue,
      data: H.rssXML(
        title: "Teardown InFlight",
        feedURL: feedURL,
        episodes: [
          ("teardown-inflight-ep", "Pick", Date(timeIntervalSince1970: 1_950_000_000))
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1102))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(feedURL.rawValue) },
      { @MainActor in "Expected RSS request to be in flight before teardown" }
    )

    collector.tearDown()

    try await Wait.until(
      { @MainActor in await H.session.cancelledRequests.contains(feedURL.rawValue) },
      { @MainActor in
        let cancelled = await H.session.cancelledRequests
        return "Expected RSS request to be cancelled after teardown; got \(cancelled)"
      }
    )

    semaphore.signal()

    #expect(collector.visiblePicks.isEmpty)
    #expect(collector.bannerState == .hidden)
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: Teardown Cancels Pending Debouncer Action

  @Test("tearDown cancels a pending stable-source debouncer action")
  func tearDownCancelsPendingDebouncerAction() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-debouncer.rss")!)
    let postTeardownFeed = FeedURL(
      URL(string: "https://example.com/teardown-positive-sync.rss")!
    )
    await H.respondWithFeed(at: feedURL, title: "Teardown Debouncer", episodes: 1)
    await H.respondWithFeed(at: postTeardownFeed, title: "Post Teardown", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1701))]
    )

    // Debouncer's 1 s sleep is registered but not yet advanced.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    collector.tearDown()

    // Fresh pipeline for a different feed. If tearDown didn't cancel the
    // pre-tearDown debouncer, advancing past its wakeTime would also trigger
    // an RSS request for the original feedURL.
    let postTeardownSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(postTeardownSource)
    collector.recordSourcePodcasts(
      source: postTeardownSource,
      podcasts: [H.makeUnsavedRow(feedURL: postTeardownFeed, iTunesID: ITunesPodcastID(1702))]
    )

    try await H.advanceStableSourceDebounce()

    // Past the pre-tearDown wakeTime — a still-armed stale debouncer would
    // already have pushed feedURL into requests.
    try await Wait.until(
      { @MainActor in await H.session.requests.contains(postTeardownFeed.rawValue) },
      { @MainActor in
        let r = await H.session.requests
        return "Expected post-tearDown RSS request to land; got \(r)"
      }
    )

    let requests = await H.session.requests
    #expect(
      !requests.contains(feedURL.rawValue),
      "Stale debouncer fired after tearDown; got \(requests)"
    )
    #expect(collector.picks(for: source).isEmpty)
  }
}
