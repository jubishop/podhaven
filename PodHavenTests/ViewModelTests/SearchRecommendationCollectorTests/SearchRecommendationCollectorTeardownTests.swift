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

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
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
    // Hold the RSS response so processFeedURL stays suspended on
    // downloadFinished. tearDown must cancel the underlying DownloadTask,
    // which in turn cancels this handler's wait.
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

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
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
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-debouncer.rss")!)
    let postTeardownFeed = FeedURL(
      URL(string: "https://example.com/teardown-positive-sync.rss")!
    )
    await H.respondWithFeed(at: feedURL, title: "Teardown Debouncer", episodes: 1)
    await H.respondWithFeed(at: postTeardownFeed, title: "Post Teardown", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1701))]
    )

    // Wait for the debouncer's 1 s sleep to be registered, but DO NOT advance
    // time yet — the reconcile / RSS work is gated behind that sleep.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    collector.tearDown()

    // Drive a brand-new pipeline after tearDown for a different feed. With the
    // fix, the pre-tearDown debouncer is cancelled and only this fresh
    // debouncer fires; without it, advancing past the prior wakeTime would
    // also resume the stale reconcile and trigger an RSS request for feedURL.
    let postTeardownSource = SearchRecommendationCollector.Source.trending(
      genreID: 1303,
      title: "Comedy"
    )
    collector.setActiveSource(postTeardownSource)
    collector.recordSourcePodcasts(
      source: postTeardownSource,
      podcasts: [H.makeUnsavedRow(feedURL: postTeardownFeed, iTunesID: ITunesPodcastID(1702))]
    )

    try await H.advanceStableSourceDebounce()

    // Positive sync: the post-tearDown pipeline reaches RSS fan-out. Fake time
    // is now past the pre-tearDown wakeTime, so a still-armed stale debouncer
    // would already have fired its reconcile and pushed feedURL into requests.
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
