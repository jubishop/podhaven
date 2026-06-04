// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector reset tests", .container)
@MainActor final class SearchRecommendationCollectorTeardownTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  // MARK: - Test: Reset Clears Caches

  @Test("reset clears caches and the drain task")
  func resetClearsCaches() async throws {
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
      { @MainActor in "Expected picks to land before reset, got \(collector.bannerState)" }
    )

    collector.reset()

    #expect(collector.picks(for: source).isEmpty)
    #expect(collector.bannerState(for: source) == .hidden)
    #expect(collector.visiblePicks.isEmpty)
    #expect(collector.bannerState == .hidden)
  }

  // MARK: - Test: Reset Cancels In-Flight Download

  @Test("reset cancels an in-flight RSS download")
  func resetCancelsInFlightDownload() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/teardown-inflight.rss")!)
    // Hold the response so processFeedURL stays suspended on downloadFinished;
    // reset must cancel the DownloadTask, which cancels this handler.
    let semaphore = await H.session.waitRespond(
      to: feedURL.rawValue,
      data: H.rssXML(
        title: "Reset InFlight",
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
      { @MainActor in "Expected RSS request to be in flight before reset" }
    )

    collector.reset()

    try await Wait.until(
      { @MainActor in await H.session.cancelledRequests.contains(feedURL.rawValue) },
      { @MainActor in
        let cancelled = await H.session.cancelledRequests
        return "Expected RSS request to be cancelled after reset; got \(cancelled)"
      }
    )

    semaphore.signal()

    #expect(collector.visiblePicks.isEmpty)
    #expect(collector.bannerState == .hidden)
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: Reset Cancels Pending Debouncer Action

  @Test("reset cancels a pending stable-source debouncer action")
  func resetCancelsPendingDebouncerAction() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/reset-debouncer.rss")!)
    let postResetFeed = FeedURL(
      URL(string: "https://example.com/reset-positive-sync.rss")!
    )
    await H.respondWithFeed(at: feedURL, title: "Reset Debouncer", episodes: 1)
    await H.respondWithFeed(at: postResetFeed, title: "Post Reset", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(1701))]
    )

    // Debouncer's stable-source sleep is registered but not yet advanced.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)

    collector.reset()

    // Fresh pipeline for a different feed. If reset didn't cancel the
    // pre-reset debouncer, advancing past its wakeTime would also trigger
    // an RSS request for the original feedURL.
    let postResetSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(postResetSource)
    collector.recordSourcePodcasts(
      source: postResetSource,
      podcasts: [H.makeUnsavedRow(feedURL: postResetFeed, iTunesID: ITunesPodcastID(1702))]
    )

    try await H.advanceStableSourceDebounce()

    // Past the pre-reset wakeTime — a still-armed stale debouncer would
    // already have pushed feedURL into requests.
    try await Wait.until(
      { @MainActor in await H.session.requests.contains(postResetFeed.rawValue) },
      { @MainActor in
        let r = await H.session.requests
        return "Expected post-reset RSS request to land; got \(r)"
      }
    )

    let requests = await H.session.requests
    #expect(
      !requests.contains(feedURL.rawValue),
      "Stale debouncer fired after reset; got \(requests)"
    )
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: Reset During In-Flight Reconcile Does Not Resurrect State

  // The debouncer fires its action body, which awaits `reconcileAndIngest`,
  // which suspends in `firstObservationEmission`. If reset() lands during
  // that suspend, cancellation is swallowed by the observation's catch and
  // the reconcile would otherwise continue into `applyReconciledRanking`,
  // re-creating the typed overlay / temporary cache and queuing RSS fetches
  // after teardown. The Task.isCancelled guard between the observation and
  // the ranking apply prevents that resurrection.
  @Test("reset during an in-flight reconcile does not recreate overlay or fetch RSS")
  func resetDuringInFlightReconcileDoesNotResurrectState() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let staleFeed = FeedURL(URL(string: "https://example.com/reset-during-reconcile.rss")!)
    let postResetFeed = FeedURL(URL(string: "https://example.com/reset-during-fence.rss")!)
    await H.respondWithFeed(at: staleFeed, title: "Stale Reconcile", episodes: 1)
    await H.respondWithFeed(at: postResetFeed, title: "Post Reset Fence", episodes: 1)

    let typedSource = SearchRecommendationCollector.Source.search(query: "reconcile")
    collector.setActiveSource(typedSource)
    collector.recordSourcePodcasts(
      source: typedSource,
      podcasts: [H.makeUnsavedRow(feedURL: staleFeed, iTunesID: ITunesPodcastID(8001))]
    )

    // Wake the debouncer: action body is scheduled to hop into MainActor and
    // run reconcileAndIngest. reset() below runs synchronously on MainActor
    // before that hop is serviced, so the reconcile sees a cancelled task
    // when it resumes from firstObservationEmission.
    try await H.fakeSleeper.waitForSleepRequests(count: 1)
    await H.fakeSleeper.advanceTime(by: SearchRecommendationCollector.stableSourceDebounce)

    collector.reset()

    // Fence with a fresh pipeline. Once its RSS lands, every reasonable
    // continuation of the cancelled reconcile has had time to fire.
    let postResetSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: nil, title: "Top")
    )
    collector.setActiveSource(postResetSource)
    collector.recordSourcePodcasts(
      source: postResetSource,
      podcasts: [H.makeUnsavedRow(feedURL: postResetFeed, iTunesID: ITunesPodcastID(8002))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in await H.session.requests.contains(postResetFeed.rawValue) },
      { @MainActor in
        let r = await H.session.requests
        return "Expected post-reset RSS request to land; got \(r)"
      }
    )

    let requests = await H.session.requests
    #expect(
      !requests.contains(staleFeed.rawValue),
      "Reset should bail the in-flight reconcile; instead RSS fired for \(staleFeed.rawValue)"
    )
    #expect(collector.picks(for: typedSource).isEmpty)
    #expect(collector.bannerState(for: typedSource) == .hidden)
  }
}
