// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchDiscoveryListViewModel live-swap tests", .container)
@MainActor final class SearchDiscoveryLiveSwapTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  @DynamicInjected(\.repo) private var repo

  // MARK: - Fixtures

  // Drives the collector to scored picks for the given feeds and returns a
  // view model projecting them, mirroring the ingest-tests happy path.
  private func makeViewModelWithPicks(
    feeds: [(feedURL: FeedURL, iTunesID: ITunesPodcastID, episodes: Int)]
  ) async throws -> SearchDiscoveryListViewModel {
    let collector = SearchRecommendationCollector()
    try await H.primeEngine(embeddable: H.makeScriptedEmbeddable())

    for feed in feeds {
      await H.respondWithFeed(at: feed.feedURL, title: "Discovery", episodes: feed.episodes)
    }

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: feeds.map { H.makeUnsavedRow(feedURL: $0.feedURL, iTunesID: $0.iTunesID) }
    )
    try await H.advanceStableSourceDebounce()

    let expectedPicks = feeds.reduce(0) { $0 + $1.episodes }
    try await Wait.until(
      { @MainActor in collector.picks(for: source).count == expectedPicks },
      { @MainActor in
        "Expected \(expectedPicks) picks, got \(collector.picks(for: source).count)"
      }
    )

    return SearchDiscoveryListViewModel(collector: collector, source: source)
  }

  // Saves a one-episode series whose episode carries the given mediaGUID, so
  // the DB row either matches a pick exactly (same feed) or collides with it
  // across feeds (same guid+mediaURL under a different podcast).
  private func insertRow(feedURL: FeedURL, mediaGUID: MediaGUID) async throws {
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: mediaGUID.guid, mediaURL: mediaGUID.mediaURL)
        ]
      )
    )
  }

  // MARK: - Test: Live Swap

  @Test("saving a pick's episode swaps its row to .saved in place")
  func savedRowSwapsInPlace() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/live-swap.rss")!)
    let viewModel = try await makeViewModelWithPicks(
      feeds: [(feedURL: feedURL, iTunesID: ITunesPodcastID(7101), episodes: 3)]
    )
    let picks = viewModel.collector.picks(for: viewModel.source)
    let target = try #require(picks.first)

    try await withRunningDiscoveryObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.count == picks.count },
        { @MainActor in
          "Expected \(picks.count) entries, got \(viewModel.episodeList.filteredEntries.count)"
        }
      )
      #expect(viewModel.episodeList.filteredEntries.allSatisfy { $0.episodeID == nil })
      let orderBefore = viewModel.episodeList.filteredEntryIDs

      try await insertRow(feedURL: feedURL, mediaGUID: target.id)

      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries[id: target.id]?.episodeID != nil
        },
        { @MainActor in "Expected pick \(target.id) to swap to a saved row" }
      )

      let swapped = try #require(viewModel.episodeList.filteredEntries[id: target.id])
      #expect(swapped.feedURL == feedURL)
      #expect(swapped.cacheStatus == .uncached)
      #expect(viewModel.episodeList.filteredEntryIDs == orderBefore)

      let untouched = picks.dropFirst().map(\.id)
      for id in untouched {
        #expect(viewModel.episodeList.filteredEntries[id: id]?.episodeID == nil)
      }
    }
  }

  // MARK: - Test: Cross-Feed Disambiguation

  // Episode uniqueness is per podcast, so the same (guid, mediaURL) can exist
  // under multiple feeds. A row saved under a different feed than the pick's
  // must not swap in; only the pick's own feed qualifies.
  @Test("a row with the same mediaGUID under another feed does not swap in")
  func crossFeedRowDoesNotSwap() async throws {
    let feedX = FeedURL(URL(string: "https://example.com/cross-feed-x.rss")!)
    let feedY = FeedURL(URL(string: "https://example.com/cross-feed-y.rss")!)
    let foreignFeed = FeedURL(URL(string: "https://example.com/cross-feed-foreign.rss")!)
    let viewModel = try await makeViewModelWithPicks(
      feeds: [
        (feedURL: feedX, iTunesID: ITunesPodcastID(7201), episodes: 1),
        (feedURL: feedY, iTunesID: ITunesPodcastID(7202), episodes: 1),
      ]
    )
    let picks = viewModel.collector.picks(for: viewModel.source)
    let pickA = try #require(picks.first { $0.feedURL == feedX })
    let pickB = try #require(picks.first { $0.feedURL == feedY })

    try await withRunningDiscoveryObservationLoop(viewModel) {
      // The foreign row lands first, so any emission carrying pickB's row
      // also carries it: once pickB swaps, pickA staying unsaved proves the
      // feed gate rejected the foreign row rather than not having seen it.
      try await insertRow(feedURL: foreignFeed, mediaGUID: pickA.id)
      try await insertRow(feedURL: feedY, mediaGUID: pickB.id)

      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries[id: pickB.id]?.episodeID != nil
        },
        { @MainActor in "Expected pick \(pickB.id) to swap to a saved row" }
      )

      #expect(viewModel.episodeList.filteredEntries[id: pickA.id]?.episodeID == nil)
    }
  }

  // MARK: - Test: Same-GUID Owner Swap

  @Test("saved row clears when the visible same-mediaGUID owner changes feed")
  func savedRowClearsWhenVisibleOwnerChangesFeed() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = ScriptedEmbeddable { text in
      if text.contains("First Owner") { return [1, 0, 0] }
      if text.contains("Second Owner") { return [0.9, 0.1, 0] }
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
    try await H.primeEngine(embeddable: scripted)

    let firstFeed = FeedURL(URL(string: "https://example.com/owner-first.rss")!)
    let secondFeed = FeedURL(URL(string: "https://example.com/owner-second.rss")!)
    let sharedGUID = "same-visible-guid"
    await H.session.respond(
      to: firstFeed.rawValue,
      data: H.rssXML(
        title: "First Owner Feed",
        feedURL: firstFeed,
        episodes: [
          (
            sharedGUID,
            "First Owner Pick",
            Date(timeIntervalSince1970: 1_700_000_000)
          )
        ]
      )
    )
    await H.session.respond(
      to: secondFeed.rawValue,
      data: H.rssXML(
        title: "Second Owner Feed",
        feedURL: secondFeed,
        episodes: [
          (
            sharedGUID,
            "Second Owner Pick",
            Date(timeIntervalSince1970: 1_800_000_000)
          )
        ]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [
        H.makeUnsavedRow(feedURL: firstFeed, iTunesID: ITunesPodcastID(7301)),
        H.makeUnsavedRow(feedURL: secondFeed, iTunesID: ITunesPodcastID(7302)),
      ]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      {
        @MainActor in
        collector.picks(for: source).first?.feedURL == firstFeed
      },
      { @MainActor in "Expected first owner to win initial coalescing" }
    )

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    viewModel.syncEntries(for: viewModel.discoveryListState)
    let firstPick = try #require(collector.picks(for: source).first)

    try await withRunningDiscoveryObservationLoop(viewModel) {
      try await insertRow(feedURL: firstFeed, mediaGUID: firstPick.id)
      try await Wait.until(
        {
          @MainActor in
          let entry = viewModel.episodeList.filteredEntries[id: firstPick.id]
          return entry?.feedURL == firstFeed && entry?.episodeID != nil
        },
        { @MainActor in "Expected first owner to be shown as saved" }
      )

      collector.removePick(mediaGUID: firstPick.id, feedURL: firstFeed)
      try await Wait.until(
        {
          @MainActor in
          collector.picks(for: source).first?.feedURL == secondFeed
        },
        { @MainActor in "Expected second owner to become visible" }
      )

      viewModel.syncEntries(for: viewModel.discoveryListState)

      try await Wait.until(
        {
          @MainActor in
          let entry = viewModel.episodeList.filteredEntries[id: firstPick.id]
          return entry?.feedURL == secondFeed && entry?.episodeID == nil
        },
        { @MainActor in
          let entry = viewModel.episodeList.filteredEntries[id: firstPick.id]
          return
            "Expected unsaved second owner row, got \(String(describing: entry?.feedURL)), id=\(String(describing: entry?.episodeID))"
        }
      )
    }
  }

  // MARK: - Test: Empty Pick Set

  @Test("an empty pick set starts no observation")
  func emptyPickSetStartsNoObservation() async throws {
    let collector = SearchRecommendationCollector()
    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)

    // Returning at all proves no observation stream was entered.
    await viewModel.observeSavedEpisodes()

    #expect(viewModel.episodeList.allEntries.isEmpty)
  }
}
