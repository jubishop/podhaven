// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector removal tests", .container)
@MainActor final class SearchRecommendationCollectorRemovalTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  // MARK: - Test: Post-Action Removal

  @Test("removePick drops the entry from visible picks")
  func postActionRemoval() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/remove.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Remove", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(505))]
    )
    try await H.advanceStableSourceDebounce()

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
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

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
    await H.session.respond(to: requestedURL.rawValue, data: Data(xml.utf8))

    let source = SearchRecommendationCollector.Source.trending(genreID: nil, title: "Top")
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: requestedURL, iTunesID: ITunesPodcastID(1901))]
    )
    try await H.advanceStableSourceDebounce()

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
