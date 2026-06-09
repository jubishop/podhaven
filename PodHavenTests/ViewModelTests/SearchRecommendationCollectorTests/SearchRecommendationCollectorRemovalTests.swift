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

  // MARK: - Test: removePick Clears Duplicate MediaGUID Entries

  @Test("duplicate MediaGUID picks project highest-ranked pick and clean up every owner")
  func duplicateMediaGUIDPicksProjectHighestRankedPickAndCleanUpEveryOwner() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = ScriptedEmbeddable { text in
      if text.contains("Older Higher Rank Pick") { return [1, 0, 0] }
      if text.contains("Newer Lower Rank Pick") { return [0, 1, 0] }
      if text.contains("of Signal") {
        if text.contains("Episode 0") { return [1, 0, 0] }
        if text.contains("Episode 1") { return [0, 1, 0] }
        return [0, 0, 1]
      }
      return [1, 0, 0]
    }
    try await H.primeEngine(embeddable: scripted)

    let firstFeedURL = FeedURL(URL(string: "https://example.com/aggregate-feed.rss")!)
    let secondFeedURL = FeedURL(URL(string: "https://example.com/section-feed.rss")!)
    let higherRankedEpisode = (
      guid: "shared-media-guid",
      title: "Older Higher Rank Pick",
      pubDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let newerLowerRankedEpisode = (
      guid: "shared-media-guid",
      title: "Newer Lower Rank Pick",
      pubDate: Date(timeIntervalSince1970: 1_800_000_000)
    )
    await H.session.respond(
      to: firstFeedURL.rawValue,
      data: H.rssXML(
        title: "Aggregate Feed",
        feedURL: firstFeedURL,
        episodes: [higherRankedEpisode]
      )
    )
    await H.session.respond(
      to: secondFeedURL.rawValue,
      data: H.rssXML(
        title: "Section Feed",
        feedURL: secondFeedURL,
        episodes: [newerLowerRankedEpisode]
      )
    )

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [
        H.makeUnsavedRow(feedURL: firstFeedURL, iTunesID: ITunesPodcastID(2600)),
        H.makeUnsavedRow(feedURL: secondFeedURL, iTunesID: ITunesPodcastID(2601)),
      ]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      {
        @MainActor in
        let requests = await H.session.requests
        return requests.contains(firstFeedURL.rawValue)
          && requests.contains(secondFeedURL.rawValue)
          && collector.visiblePicks.first?.episode.title == "Older Higher Rank Pick"
      },
      { @MainActor in
        let requests = await H.session.requests
        let titles = collector.visiblePicks.map(\.episode.title)
        return
          "Expected higher-ranked duplicate pick after both feeds scored; requests=\(requests), titles=\(titles)"
      }
    )
    #expect(collector.visiblePicks.count == 1)
    #expect(collector.bannerState(for: source) == .loaded(count: 1))

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    viewModel.syncEntries(for: viewModel.discoveryListState)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 1 },
      { @MainActor in
        "Expected discovery projection to de-duplicate picks, got \(viewModel.episodeList.filteredEntries.count)"
      }
    )
    #expect(viewModel.episodeList.filteredEntries.first?.title == "Older Higher Rank Pick")

    let visibleEpisode = try #require(viewModel.episodeList.filteredEntries.first)
    viewModel.queueEpisodeOnTop(visibleEpisode)

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected every duplicate pick to be removed; \(collector.visiblePicks.count) remain"
      }
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

  // MARK: - Test: View Model Drives removePick End-To-End

  // Each discovery list owns a SearchDiscoveryListViewModel for its source.
  // This exercises the happy path: a row action through that view-model
  // materializes the episode and removes the pick from the collector.
  @Test("queueEpisodeOnTop removes the pick after success")
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

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    let pick = collector.visiblePicks[0]
    viewModel.queueEpisodeOnTop(ListedEpisode(pick.episode))

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected pick to be removed after queue action; \(collector.visiblePicks.count) remain"
      }
    )
  }

  // MARK: - Test: Bulk Action Drives removePick End-To-End

  // The multi-select toolbar's consuming bulk actions drop every acted-on pick,
  // mirroring the per-row hook: projecting the picks, selecting them, and
  // queueing the selection must empty the discovery list.
  @Test("addSelectedEpisodesToTopOfQueue removes the selected picks after success")
  func bulkActionRemovesSelectedPicks() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)

    let feedURL = FeedURL(URL(string: "https://example.com/bulk-vm.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Bulk VM", episodes: 2)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(2400))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in !collector.visiblePicks.isEmpty },
      { @MainActor in "Expected picks to land, got \(collector.visiblePicks.count)" }
    )

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    let pickCount = collector.visiblePicks.count
    viewModel.syncEntries(for: viewModel.discoveryListState)

    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == pickCount },
      { @MainActor in
        "Expected \(pickCount) entries to project, got \(viewModel.episodeList.filteredEntries.count)"
      }
    )

    viewModel.selectAllEntries()
    viewModel.addSelectedEpisodesToTopOfQueue()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected picks to be removed after bulk queue; \(collector.visiblePicks.count) remain"
      }
    )
  }

  // MARK: - Test: Caching A Pick Is Non-Consuming

  // Caching / save-in-cache don't change candidacy, so — like tagging — they
  // leave the pick in the discovery list. Only candidate-breaking actions
  // (play / queue / rate / finish) remove it.
  @Test("caching a discovery pick leaves it in the list")
  func cachingDiscoveryPickIsNonConsuming() async throws {
    let collector = SearchRecommendationCollector()
    let scripted = H.makeScriptedEmbeddable()
    try await H.primeEngine(embeddable: scripted)
    Container.shared.cacheManager().start()

    let feedURL = FeedURL(URL(string: "https://example.com/cache-noremove.rss")!)
    await H.respondWithFeed(at: feedURL, title: "Cache NoRemove", episodes: 1)

    let source = SearchRecommendationCollector.Source.trending(.init(genreID: nil, title: "Top"))
    collector.setActiveSource(source)
    collector.recordSourcePodcasts(
      source: source,
      podcasts: [H.makeUnsavedRow(feedURL: feedURL, iTunesID: ITunesPodcastID(606))]
    )
    try await H.advanceStableSourceDebounce()

    try await Wait.until(
      { @MainActor in collector.visiblePicks.count == 1 },
      { @MainActor in "Expected one pick to land, got \(collector.visiblePicks.count)" }
    )

    let pick = collector.visiblePicks[0]
    let listed = ListedEpisode(pick.episode)
    let episodeID = try await listed.getOrCreatePodcastEpisode().id

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    viewModel.cacheEpisode(listed)

    // Drive the cache to completion — well past the point where a consuming
    // action would have removed the pick via didPerformAction.
    let taskID = try await CacheHelpers.waitForDownloadTask(episodeID)
    try await CacheHelpers.waitForResumed(taskID)
    _ = try await CacheHelpers.simulateBackgroundFinish(taskID)
    _ = try await CacheHelpers.waitForCached(episodeID)

    #expect(
      collector.visiblePicks.contains { $0.episode.mediaGUID == pick.episode.mediaGUID },
      "Caching is non-consuming; the pick must remain in the list"
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

    let viewModel = SearchDiscoveryListViewModel(collector: collector, source: source)
    viewModel.queueEpisodeOnTop(ListedEpisode(pick.episode))

    try await Wait.until(
      { @MainActor in collector.visiblePicks.isEmpty },
      { @MainActor in
        "Expected pick to be removed after queue action; \(collector.visiblePicks.count) remain"
      }
    )

    let allRows = try await repo.allPodcasts(AppDB.noOp)
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
