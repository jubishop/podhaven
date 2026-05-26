// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

@Suite("of SearchRecommendationCollector removal tests", .container)
@MainActor final class SearchRecommendationCollectorRemovalTests {
  private typealias H = SearchRecommendationCollectorTestHelpers

  @DynamicInjected(\.repo) private var repo

  // MARK: - Test: Post-Action Removal

  @Test("removePick drops the entry from visible picks")
  func postActionRemoval() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/remove.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Remove", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
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
    collector.removePick(mediaGUID: removed)

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

    // atom:link rel="self" points at a different URL than the one downloaded.
    // PodcastFeed sets unsavedPodcast.feedURL from atom:link, so the rendered
    // ListedEpisode.feedURL is canonical but the cache key is the requested URL.
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

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
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
    #expect(
      pick.episode.feedURL == parsedSelfURL,
      "Test setup invariant: parsed feed URL must differ from requested URL"
    )

    let listed = ListedEpisode(pick.episode)
    collector.removePick(mediaGUID: listed.mediaGUID)

    #expect(
      collector.visiblePicks.isEmpty,
      "Expected pick to be removed even when its feedURL differs from the cache key"
    )
  }

  // MARK: - Test: removePick'd Entry Is Not Re-Queued On Scoring-Context Re-Open

  // After the user clears the last pick, the entry must not come back the
  // next time the engine cools (cache cleared) and warms again — the watcher
  // would otherwise treat it as "empty because scoring was unavailable" and
  // re-fetch RSS for a podcast the user has explicitly dismissed.
  @Test("removed pick is not re-fetched after a scoring-context close → open cycle")
  func removedPickSurvivesScoringContextCycle() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()

    Container.shared.contextualEmbedding.reset()
      .register { ContextualEmbedding(embedding: scripted) }
      .scope(.cached)
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: scripted)

    let engine = Container.shared.recommendationEngine()
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in engine.hasScoringContext },
      { @Sendable in "Expected scoring context to land" }
    )

    let feedURL = FeedURL(URL(string: "https://example.com/exhausted-survives-cycle.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Survives Cycle", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(2500))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count == 1 },
      { @MainActor in "Expected one pick to land, got \(collector.visiblePicks.count)" }
    )

    let initialRequests = await H.session.requests.filter { $0 == feedURL.rawValue }.count
    #expect(initialRequests == 1, "Test premise: pipeline should have made exactly one RSS request")

    let pickGUID = collector.visiblePicks[0].episode.mediaGUID
    collector.removePick(mediaGUID: pickGUID)
    #expect(collector.visiblePicks.isEmpty)

    // Drive the engine through close → open by unrating signals (cache=nil)
    // and then re-rating them (cache=context). The watcher inside the
    // collector fires `handleScoringContextBecameAvailable` on the open edge.
    for signal in signals {
      _ = try await repo.updateRating(signal.id, rating: nil)
    }
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in !engine.hasScoringContext },
      { @Sendable in "Expected scoring context to close after unrating signals" }
    )

    let restoredRatings: [EpisodeRating] = [.loved, .liked, .liked]
    for (signal, rating) in zip(signals, restoredRatings) {
      _ = try await repo.updateRating(signal.id, rating: rating)
    }
    try await RecommendationHelpers.untilAdvancing(
      { @Sendable in engine.hasScoringContext },
      { @Sendable in "Expected scoring context to reopen after re-rating signals" }
    )

    // Use a positive control to fence the assertion: a new feed kicked off
    // after the re-open. By the time its pipeline completes the watcher has
    // had every opportunity to re-queue the dismissed entry, so a stable
    // request count for `feedURL` proves the dismissed pick stays dismissed.
    let controlFeedURL = FeedURL(URL(string: "https://example.com/post-cycle-control.rss")!)
    await H.respondWithFeed(at: controlFeedURL, title: "Post Cycle Control", episodes: 1)
    let controlSource = SearchRecommendationCollector.Source.trending(
      .init(genreID: 1303, title: "Comedy")
    )
    collector.setActiveSource(controlSource)
    collector.recordSourcePodcasts(
      source: controlSource,
      podcasts: [H.makeUnsavedRow(feedURL: controlFeedURL, iTunesID: ITunesPodcastID(2501))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in
        if case .loaded = collector.bannerState(for: controlSource) { return true }
        return false
      },
      { @MainActor in
        "Expected control pick to land after the cycle, got \(collector.bannerState(for: controlSource))"
      }
    )

    let finalRequests = await H.session.requests.filter { $0 == feedURL.rawValue }.count
    #expect(
      finalRequests == 1,
      "Expected dismissed feed to NOT be re-fetched after close→open; got \(finalRequests) requests"
    )
    #expect(collector.picks(for: source).isEmpty)
  }

  // MARK: - Test: actionsViewModel Drives removePick End-To-End

  // SearchViewModel owns one SearchDiscoveryActionsViewModel that's threaded
  // through the discovery list's init, so it survives every body re-render.
  // This exercises the happy path: a row action through that view-model
  // materializes the episode and removes the pick from the collector.
  @Test("actionsViewModel.queueEpisodeOnTop removes the pick after success")
  func actionsViewModelRemovesPickAfterQueueAction() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/actions-vm.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Actions VM", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(2200))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count == 1 },
      { @MainActor in "Expected one pick to land, got \(collector.visiblePicks.count)" }
    )

    let actionsViewModel = SearchDiscoveryActionsViewModel(collector: collector)
    let pick = collector.visiblePicks[0]
    actionsViewModel.queueEpisodeOnTop(ListedEpisode(pick.episode))

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected pick to be removed after queue action; \(collector.visiblePicks.count) remain"
      }
    )
  }

  // MARK: - Test: Pick Action Reuses Existing Podcast Row Across atom:self Shift

  // Regression for the iTunesID-identity bug: the iTunes row brings (A, I),
  // RSS publishes atom:self=B. Without threading iTunesID into the pick's
  // UnsavedPodcast, the queue action's upsert misses the existing row by
  // feedURL (B ≠ A) AND by iTunesID (because iTunesID is nil on the pick),
  // and inserts a duplicate podcast row.
  @Test(
    "queueEpisodeOnTop reuses the existing podcast row when RSS atom:self differs from iTunes feedURL"
  )
  func actionsViewModelReusesExistingPodcastWhenAtomSelfDiffers() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let requestedURL = FeedURL(URL(string: "https://example.com/itunes-source-23.rss")!)
    let parsedSelfURL = FeedURL(URL(string: "https://example.com/canonical-self-23.rss")!)
    let iTunesID = ITunesPodcastID(2300)

    // Pre-insert a saved-but-unsubscribed podcast at the iTunes (slot) URL.
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: requestedURL,
          iTunesID: iTunesID,
          title: "Existing Saved",
          subscriptionDate: nil
        ),
        unsavedEpisodes: []
      )
    )

    // RSS publishes atom:link rel="self" pointing at a different URL.
    let xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" \
      xmlns:atom="http://www.w3.org/2005/Atom">
        <channel>
          <title>Canonical Differs 23</title>
          <link>\(requestedURL.absoluteString)</link>
          <description>Canonical Differs 23 description</description>
          <itunes:image href="https://example.com/image.png" />
          <atom:link rel="self" href="\(parsedSelfURL.absoluteString)" />
          <item>
            <guid isPermaLink="false">canon-pick-23</guid>
            <title>Canonical Pick 23</title>
            <pubDate>Mon, 14 Nov 2023 22:13:20 +0000</pubDate>
            <enclosure url="https://example.com/audio/canon-pick-23.mp3" type="audio/mpeg" length="0" />
            <description>Canonical Pick 23 description</description>
          </item>
        </channel>
      </rss>
      """
    await H.session.respond(to: requestedURL.rawValue, data: Data(xml.utf8))

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: requestedURL, iTunesID: iTunesID)]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count == 1 },
      { @MainActor in "Expected one pick to land, got \(collector.visiblePicks.count)" }
    )

    let pick = collector.visiblePicks[0]
    #expect(
      pick.episode.feedURL == parsedSelfURL,
      "Test setup invariant: pick's feedURL must reflect the parsed atom:self URL"
    )

    let actionsViewModel = SearchDiscoveryActionsViewModel(collector: collector)
    actionsViewModel.queueEpisodeOnTop(ListedEpisode(pick.episode))

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected pick to be removed after queue action; \(collector.visiblePicks.count) remain"
      }
    )

    let allRows = try await repo.allPodcasts(AppDB.NoOp)
    let matchingITunes = allRows.filter { $0.iTunesID == iTunesID }
    #expect(
      matchingITunes.count == 1,
      """
      Expected exactly one podcast row with iTunesID; \
      got \(matchingITunes.map(\.feedURL.absoluteString))
      """
    )
    #expect(
      matchingITunes.first?.id == savedSeries.podcast.id,
      "Expected the existing podcast row to be reused"
    )

    let orphans = allRows.filter { $0.feedURL == parsedSelfURL }
    #expect(
      orphans.isEmpty,
      "Expected no duplicate podcast at the atom:self URL; got \(orphans.map(\.toString))"
    )
  }

  // MARK: - Test: saveEpisodeInCache Through ManagingEpisodes Dispatch

  // EpisodeContextMenuViewModifier<ViewModel: ManagingEpisodes> dispatches
  // statically through the constraint. If saveEpisodeInCache only lives in
  // an extension, the override is bypassed — must be in the protocol itself.
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
