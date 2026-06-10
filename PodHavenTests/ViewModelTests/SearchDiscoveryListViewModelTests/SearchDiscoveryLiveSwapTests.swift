// Copyright Justin Bishop, 2026

import AVFoundation
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

  @Test("a saved pick swaps when RSS publishes a different feed URL")
  func savedRowSwapsWhenParsedFeedURLDiffers() async throws {
    let collector = SearchRecommendationCollector()
    try await H.primeEngine(embeddable: H.makeScriptedEmbeddable())

    let requestedFeed = FeedURL(URL(string: "https://example.com/requested-swap.rss")!)
    let parsedFeed = FeedURL(URL(string: "https://example.com/parsed-swap.rss")!)
    let guid = "parsed-feed-live-swap"
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" \
      xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>Parsed Swap</title>
          <link>\(requestedFeed.absoluteString)</link>
          <description>Parsed Swap description</description>
          <itunes:image href="https://example.com/image.png" />
          <atom:link rel="self" href="\(parsedFeed.absoluteString)" />
          <item>
            <guid isPermaLink="false">\(guid)</guid>
            <title>Parsed Swap Pick</title>
            <pubDate>Mon, 14 Nov 2023 22:13:20 +0000</pubDate>
            <enclosure url="https://example.com/audio/\(guid).mp3" type="audio/mpeg" length="0" />
            <description>Parsed Swap Pick description</description>
          </item>
        </channel>
      </rss>
      """
    let data = Data(xml.utf8)
    await H.session.respond(to: requestedFeed.rawValue, data: data)
    await H.session.respond(to: parsedFeed.rawValue, data: data)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: requestedFeed, iTunesID: ITunesPodcastID(7401))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      {
        @MainActor in
        let pick = collector.picks(for: source).first
        return pick?.feedURL == requestedFeed && pick?.episode.feedURL == parsedFeed
      },
      { @MainActor in
        let pick = collector.picks(for: source).first
        return
          "Expected requested-feed collector key and parsed-feed episode row, got \(String(describing: pick))"
      }
    )

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)

    try await withRunningDiscoveryObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.count == 1 },
        { @MainActor in
          "Expected one entry, got \(viewModel.episodeList.filteredEntries.count)"
        }
      )
      let pick = try #require(collector.picks(for: source).first)
      let initial = try #require(viewModel.episodeList.filteredEntries[id: pick.id])
      #expect(initial.feedURL == parsedFeed)
      #expect(initial.episodeID == nil)

      _ = try await initial.getOrCreatePodcastEpisode()

      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries[id: pick.id]?.episodeID != nil
        },
        { @MainActor in "Expected parsed-feed pick \(pick.id) to swap to a saved row" }
      )

      let swapped = try #require(viewModel.episodeList.filteredEntries[id: pick.id])
      #expect(swapped.feedURL == parsedFeed)
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

  // MARK: - Test: Candidate Re-Gate

  // Detail-screen mutating actions materialize the episode without going
  // through the row-action removal hook; the saved-row observation must drop
  // the pick once its DB row fails the discovery candidate gate.
  @Test("a detail-screen queue action removes the pick from the collector")
  func detailQueueActionRemovesPick() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/detail-regate.rss")!)
    let viewModel = try await makeViewModelWithPicks(
      feeds: [(feedURL: feedURL, iTunesID: ITunesPodcastID(7501), episodes: 2)]
    )
    let picks = viewModel.collector.picks(for: viewModel.source)
    let target = try #require(picks.first)
    let untouched = try #require(picks.last)

    try await withRunningDiscoveryObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.count == picks.count },
        { @MainActor in
          "Expected \(picks.count) entries, got \(viewModel.episodeList.filteredEntries.count)"
        }
      )
      let entry = try #require(viewModel.episodeList.filteredEntries[id: target.id])
      let detailViewModel = EpisodeDetailViewModel(listedEpisode: entry)

      detailViewModel.appendToQueue()

      try await Wait.until(
        { @MainActor in
          !viewModel.collector.picks(for: viewModel.source).contains { $0.id == target.id }
        },
        { @MainActor in "Expected queued pick \(target.id) to be removed from the collector" }
      )
      #expect(viewModel.collector.picks(for: viewModel.source).map(\.id) == [untouched.id])
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries[id: target.id] == nil },
        { @MainActor in "Expected queued pick \(target.id) to leave the projected list" }
      )
    }
  }

  @Test("an onDeck-only transition removes the pick from the collector")
  func onDeckOnlyTransitionRemovesPick() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/on-deck-regate.rss")!)
    let viewModel = try await makeViewModelWithPicks(
      feeds: [(feedURL: feedURL, iTunesID: ITunesPodcastID(7601), episodes: 2)]
    )
    let picks = viewModel.collector.picks(for: viewModel.source)
    let target = try #require(picks.first)
    let untouched = try #require(picks.last)

    try await withRunningDiscoveryObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.count == picks.count },
        { @MainActor in
          "Expected \(picks.count) entries, got \(viewModel.episodeList.filteredEntries.count)"
        }
      )
      let entry = try #require(viewModel.episodeList.filteredEntries[id: target.id])

      let podcastEpisode = try await entry.getOrCreatePodcastEpisode()

      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries[id: target.id]?.episodeID != nil
        },
        { @MainActor in "Expected pick \(target.id) to swap to a saved row" }
      )

      Container.shared.stateManager().setOnDeck(podcastEpisode)

      try await Wait.until(
        { @MainActor in
          !viewModel.collector.picks(for: viewModel.source).contains { $0.id == target.id }
        },
        { @MainActor in "Expected onDeck pick \(target.id) to be removed from the collector" }
      )
      #expect(viewModel.collector.picks(for: viewModel.source).map(\.id) == [untouched.id])
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries[id: target.id] == nil },
        { @MainActor in "Expected onDeck pick \(target.id) to leave the projected list" }
      )
    }
  }

  // MARK: - Test: Tick-Free Task Key

  // The task key must restart the observation on episode transitions without
  // tracking the onDeck broadcast itself, which playback mutates every tick;
  // otherwise the discovery list body re-evaluates for the whole session.
  @Test("playback ticks do not invalidate the saved-observation task key")
  func playbackTickDoesNotInvalidateTaskKey() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/tick-free-key.rss")!)
    let viewModel = try await makeViewModelWithPicks(
      feeds: [(feedURL: feedURL, iTunesID: ITunesPodcastID(7701), episodes: 2)]
    )
    viewModel.syncEntries(for: viewModel.discoveryListState)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
      { @MainActor in
        "Expected 2 entries, got \(viewModel.episodeList.filteredEntries.count)"
      }
    )
    let first = try #require(viewModel.episodeList.filteredEntries.first)
    let last = try #require(viewModel.episodeList.filteredEntries.last)
    let stateManager = Container.shared.stateManager()
    stateManager.setOnDeck(try await first.getOrCreatePodcastEpisode())

    let invalidated = ThreadSafe(false)
    withObservationTracking {
      _ = viewModel.savedObservationTaskKey
    } onChange: {
      invalidated(true)
    }

    stateManager.setCurrentTime(CMTime.seconds(30))
    #expect(!invalidated())

    // The same registration must still wake for a real episode transition.
    stateManager.setOnDeck(try await last.getOrCreatePodcastEpisode())
    #expect(invalidated())
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
