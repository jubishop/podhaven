// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel tests", .container)
@MainActor final class PodcastDetailViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.userNotificationCenter) private var userNotificationCenter

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  private var notificationCenter: FakeUserNotificationCenter {
    userNotificationCenter as! FakeUserNotificationCenter
  }

  @Test("performAppear loads a saved series and backfills its iTunes ID")
  func performAppearLoadsSavedSeriesAndBackfillsITunesID() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let iTunesID = ITunesPodcastID(1528594034)
    let savedSeries = try await insertSeriesFromFeed(
      assetName: "hardfork_short",
      feedURL: feedURL
    )

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(
        try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: iTunesID,
          title: "Hard Fork"
        )
      )
    )

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        let reloadedSeries = try await self.repo.podcastSeries(savedSeries.id)
        return viewModel.saved
          && viewModel.podcast.iTunesID == iTunesID
          && viewModel.episodeList.allEntries.count == savedSeries.episodes.count
          && reloadedSeries?.podcast.iTunesID == iTunesID
      },
      { @MainActor in
        let reloadedSeries = try await self.repo.podcastSeries(savedSeries.id)
        return """
          Expected PodcastDetailViewModel to load the saved series and backfill its iTunes ID.
          saved: \(viewModel.saved)
          podcast iTunesID: \(String(describing: viewModel.podcast.iTunesID))
          episode count: \(viewModel.episodeList.allEntries.count)
          reloaded iTunesID: \(String(describing: reloadedSeries?.podcast.iTunesID))
          """
      }
    )

    #expect(viewModel.podcast.title == savedSeries.podcast.title)
  }

  @Test("listed listable podcasts expose share URL and hydrate without parsing the feed")
  func listedListablePodcastsHydrateWithoutParsingFeed() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/listed-podcast.rss")!),
          title: "Listed Podcast",
          description: "Saved Description"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "Episode 1"),
          try Create.unsavedEpisode(title: "Episode 2"),
        ]
      )
    )
    let listablePodcast = try await fetchListablePodcast(savedSeries.id)
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))

    #expect(viewModel.shareURL == ShareURL.podcast(feedURL: savedSeries.podcast.feedURL))

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        viewModel.saved
          && viewModel.podcast.title == savedSeries.podcast.title
          && viewModel.podcast.description == savedSeries.podcast.description
          && viewModel.episodeList.allEntries.count == savedSeries.episodes.count
      },
      { @MainActor in
        """
        Expected list-backed podcast detail to hydrate saved podcast data.
        saved: \(viewModel.saved)
        title: \(viewModel.podcast.title)
        description: \(viewModel.podcast.description)
        episode count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )
  }

  @Test("listed search result podcasts preserve search metadata before hydrating saved detail")
  func listedSearchResultPodcastsPreserveInitialMetadata() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/search-target.rss")!)
    let iTunesID = ITunesPodcastID(777)
    let savedLink = try #require(URL(string: "https://example.com/saved"))
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          iTunesID: iTunesID,
          title: "Saved Podcast",
          description: "Saved Description",
          link: savedLink
        ),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "Saved Episode")]
      )
    )
    let savedPodcast = try await fetchListablePodcast(savedSeries.id)
    let searchDescription = "Search Description"
    let searchLink = try #require(URL(string: "https://example.com/search"))
    let searchResult = SavedSearchResultPodcast(
      resultFeedURL: FeedURL(URL(string: "https://example.com/search-result.rss")!),
      originalPodcast: try Create.unsavedPodcast(
        feedURL: searchResultFeedURL(),
        iTunesID: iTunesID,
        title: "Search Title",
        description: searchDescription,
        link: searchLink
      ),
      originalEpisodeCount: 5,
      originalMostRecentEpisodeDate: Date(timeIntervalSince1970: 123),
      savedPodcast: savedPodcast
    )
    let viewModel = PodcastDetailViewModel(
      listedPodcast: ListedPodcast(savedSearchResult: searchResult)
    )

    #expect(viewModel.shareURL == ShareURL.podcast(feedURL: feedURL))
    #expect(viewModel.podcast.description == searchDescription)
    #expect(viewModel.podcast.link == searchLink)

    try await viewModel.performAppear()

    #expect(viewModel.saved)
    #expect(viewModel.podcast.description == savedSeries.podcast.description)
    #expect(viewModel.podcast.link == savedLink)
  }

  @Test("performAppear parses the feed when no saved series exists")
  func performAppearParsesFeedWhenUnsaved() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: data)
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(
        try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Placeholder Title"
        )
      )
    )

    try await viewModel.performAppear()

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.loaded?.source.unsaved != nil)
    #expect(viewModel.episodeList.allEntries.isEmpty == false)
  }

  @Test("performAppear keeps preloaded unsaved series without reparsing the feed")
  func performAppearKeepsPreloadedUnsavedSeriesWithoutParsingFeed() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/preloaded-series.rss")!),
        title: "Preloaded Series"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "preloaded-1",
          title: "Episode 1",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "preloaded-2",
          title: "Episode 2",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    try await viewModel.performAppear()

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.title == unsavedSeries.unsavedPodcast.title)
    #expect(viewModel.episodeList.allEntries.map(\.title) == ["Episode 1", "Episode 2"])
  }

  @Test("shared unsaved podcast series is presented before appear")
  func unsavedPodcastSeriesIsPresentedBeforeAppear() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/immediate-series.rss")!),
        title: "Immediate Series"
      ),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "immediate-1",
          title: "Immediate Episode 1",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "immediate-2",
          title: "Immediate Episode 2",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
      ]
    )

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    #expect(viewModel.saved == false)
    #expect(viewModel.podcast.title == unsavedSeries.unsavedPodcast.title)
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.map(\.title) == [
          "Immediate Episode 1",
          "Immediate Episode 2",
        ]
      },
      { @MainActor in
        """
        Expected shared unsaved podcast series episodes to be presented before appear.
        Actual titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )
  }

  @Test("deleting an observed saved series reparses the feed into unsaved detail")
  func observedDeletionReparsesFeed() async throws {
    let feedURL = FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    let savedSeries = try await insertSeriesFromFeed(
      assetName: "hardfork_short",
      feedURL: feedURL
    )
    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(savedSeries.podcast)
    )

    try await viewModel.performAppear()
    await feedSession.respond(
      to: feedURL.rawValue,
      data: PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    )

    _ = try await repo.deletePodcast(savedSeries.id)

    try await Wait.until(
      { @MainActor in
        viewModel.saved == false
          && viewModel.podcast.loaded?.source.unsaved != nil
          && viewModel.episodeList.allEntries.isEmpty == false
      },
      { @MainActor in
        """
        Expected deleted saved podcast to reparse back into unsaved detail.
        saved: \(viewModel.saved)
        podcast: \(viewModel.podcast.toString)
        episode count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )
  }

  @Test("deleting an observed saved series alerts when feed recovery fails")
  func observedDeletionFailureAlerts() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/deleted-podcast.rss")!)
    let feedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: feedData)
    let podcastFeed = try await PodcastFeed.parse(feedData, from: feedURL)
    let savedSeries = try await repo.insertSeries(podcastFeed.toUnsavedSeries())
    let displayedPodcast = DisplayedPodcast(savedSeries.podcast)

    let viewModel = PodcastDetailViewModel(podcast: displayedPodcast)

    try await viewModel.performAppear()

    await feedSession.respond(to: feedURL.rawValue, error: URLError(.cannotLoadFromNetwork))
    _ = try await repo.deletePodcast(savedSeries.id)

    try await Wait.until(
      { @MainActor [self] in alert.config != nil },
      { @MainActor [self] in
        """
        Expected failed feed recovery after deletion to alert.
        alert presented: \(alert.config != nil)
        """
      }
    )
  }

  @Test("subscribe persists an unsaved series and its episodes")
  func subscribePersistsUnsavedSeriesAndItsEpisodes() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/subscribe.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Subscribe Me"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "episode-1", title: "Episode 1"),
        try Create.unsavedEpisode(guid: "episode-2", title: "Episode 2"),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    #expect(viewModel.saved == false)
    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in
        guard let savedSeries = try await self.repo.podcastSeries(feedURL) else { return false }
        return viewModel.saved
          && viewModel.podcast.subscribed
          && savedSeries.podcast.subscribed
          && savedSeries.episodes.count == unsavedSeries.unsavedEpisodes.count
      },
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return """
          Expected subscribe() to persist the unsaved series.
          saved: \(viewModel.saved)
          subscribed: \(viewModel.podcast.subscribed)
          repo episode count: \(savedSeries?.episodes.count ?? -1)
          """
      }
    )

    #expect(try await repo.allPodcasts(AppDB.NoOp).count == 1)
  }

  @Test("recentlyQueued sort filters to previously queued episodes and orders newest first")
  func recentlyQueuedSortFiltersAndOrdersEpisodes() async throws {
    let olderQueueDate = Date(timeIntervalSince1970: 100)
    let newerQueueDate = Date(timeIntervalSince1970: 200)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Queue Sorting"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "unqueued", title: "Not queued"),
        try Create.unsavedEpisode(
          guid: "older-queued",
          title: "Older queued",
          queueDate: olderQueueDate
        ),
        try Create.unsavedEpisode(
          guid: "newer-queued",
          title: "Newer queued",
          queueDate: newerQueueDate
        ),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    viewModel.currentSortMethod = .recentlyQueued

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newer queued", "Older queued"]
      },
      { @MainActor in
        """
        Expected recentlyQueued sort to filter and order queued episodes.
        Actual titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }

  @Test("selected episode tag helpers use saved episode tag IDs")
  func selectedEpisodeTagHelpersUseSavedEpisodeTagIDs() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tagged Detail"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "detail-tagged-1"),
          try Create.unsavedEpisode(guid: "detail-tagged-2"),
        ]
      )
    )
    let firstEpisode = savedSeries.episodes[0]
    let secondEpisode = savedSeries.episodes[1]
    let alpha = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let beta = try await repo.insertTag(UnsavedTag(name: "Beta"))
    let cherry = try await repo.insertTag(UnsavedTag(name: "Cherry"))

    try await repo.addTag(alpha.id, to: firstEpisode.id)
    try await repo.addTag(beta.id, to: firstEpisode.id)
    try await repo.addTag(beta.id, to: secondEpisode.id)
    try await repo.addTag(cherry.id, to: secondEpisode.id)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected saved podcast detail episodes to load before selection."
      }
    )

    try select(viewModel, episodeIDs: [firstEpisode.id, secondEpisode.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [beta.id])
    #expect(viewModel.selectedEpisodesTagUnion == [alpha.id, beta.id, cherry.id])
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectionHasTagData is false when any selected episode is unsaved")
  func selectionHasTagDataFalseForUnsavedSelection() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Tag Gate"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "unsaved-tag-gate-1"),
        try Create.unsavedEpisode(guid: "unsaved-tag-gate-2"),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    _ = try await repo.insertTag(UnsavedTag(name: "Alpha"))

    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
      { @MainActor in
        "Expected unsaved series episodes to seed before selection."
      }
    )

    for entry in viewModel.episodeList.allEntries {
      viewModel.episodeList.isSelected[entry.id] = true
    }

    // Bulk tag actions on unsaved selections would silently upsert just to
    // attach a tag — the gate keeps the menu hidden so the per-row
    // "no tag UI for unsaved rows" contract holds across both surfaces.
    #expect(viewModel.selectionHasTagData == false)
  }

  @Test("selectedPodcastEpisodes preserves user-visible selection order")
  func selectedPodcastEpisodesPreservesSelectionOrder() async throws {
    // Insertion order = ep1, ep2, ep3 (so DB rowid order matches that).
    // pubDates are reversed so `oldestFirst` flips the visible order to
    // [ep3, ep2, ep1] — different from any "natural" SQL ordering, which
    // is what reveals the bug if `WHERE id IN (...)` returns rows in
    // rowid order rather than the input ID order.
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Selection Order"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "sel-order-1",
            title: "Newest",
            pubDate: Date(timeIntervalSince1970: 300)
          ),
          try Create.unsavedEpisode(
            guid: "sel-order-2",
            title: "Middle",
            pubDate: Date(timeIntervalSince1970: 200)
          ),
          try Create.unsavedEpisode(
            guid: "sel-order-3",
            title: "Oldest",
            pubDate: Date(timeIntervalSince1970: 100)
          ),
        ]
      )
    )
    let newest = savedSeries.episodes[0]
    let middle = savedSeries.episodes[1]
    let oldest = savedSeries.episodes[2]

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()
    viewModel.currentSortMethod = .oldestFirst

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Oldest", "Middle", "Newest"]
      },
      { @MainActor in
        """
        Expected oldestFirst sort to flip the visible order before selecting.
        Actual titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    try select(viewModel, episodeIDs: [oldest.id, middle.id, newest.id])

    // selectedEpisodes follows filteredEntries (visible) order, so the
    // returned PodcastEpisodes must match — anything else means the
    // `WHERE id IN (...)` row-order leaked into bulk Play / Replace Queue.
    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(podcastEpisodes.map(\.id) == [oldest.id, middle.id, newest.id])
  }

  @Test("refreshing a series under newestFirst places a new episode at the top, not the bottom")
  func refreshMergesNewEpisodeAtTopUnderNewestFirstSort() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/refresh-sort.rss")!)
    let olderPubDate = Date(timeIntervalSince1970: 100)
    let newerPubDate = Date(timeIntervalSince1970: 200)
    let newestPubDate = Date(timeIntervalSince1970: 300)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Refresh Sort"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "older", title: "Older", pubDate: olderPubDate),
          try Create.unsavedEpisode(guid: "newer", title: "Newer", pubDate: newerPubDate),
        ]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        viewModel.saved
          && viewModel.episodeList.allEntries.map(\.title) == ["Newer", "Older"]
      },
      { @MainActor in
        """
        Expected initial load to present episodes in newest-first order.
        saved: \(viewModel.saved)
        titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )

    try await repo.updateSeriesFromFeed(
      podcastSeries: savedSeries,
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "newest", title: "Newest", pubDate: newestPubDate)
      ],
      existingEpisodes: []
    )

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.map(\.title) == ["Newest", "Newer", "Older"]
      },
      { @MainActor in
        """
        Expected the refreshed new episode to land at the top under .newestFirst.
        titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )
  }

  @Test("switching sorts stays correct after a refresh merges a new episode")
  func switchingSortsStaysCorrectAfterRefreshMergesANewEpisode() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/sort-switch.rss")!)
    let olderPubDate = Date(timeIntervalSince1970: 100)
    let newerPubDate = Date(timeIntervalSince1970: 200)
    let newestPubDate = Date(timeIntervalSince1970: 300)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Sort Switch"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "older", title: "Older", pubDate: olderPubDate),
          try Create.unsavedEpisode(guid: "newer", title: "Newer", pubDate: newerPubDate),
        ]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in viewModel.saved && viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        """
        Expected initial saved series to load with two episodes.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    try await repo.updateSeriesFromFeed(
      podcastSeries: savedSeries,
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "newest", title: "Newest", pubDate: newestPubDate)
      ],
      existingEpisodes: []
    )

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected the refreshed episode to be merged in (count == 3)."
      }
    )

    viewModel.currentSortMethod = .oldestFirst
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Older", "Newer", "Newest"]
      },
      { @MainActor in
        """
        Expected oldestFirst to order by pubDate ascending.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    viewModel.currentSortMethod = .newestFirst
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Newest", "Newer", "Older"]
      },
      { @MainActor in
        """
        Expected newestFirst to re-sort by pubDate descending after the merge.
        titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )
  }

  @Test("notifyNewEpisodes persists the setting and requests notification authorization")
  func notifyNewEpisodesPersistsSettingAndRequestsAuthorization() async throws {
    notificationCenter.setAuthorizationStatus(.notDetermined)

    let feedURL = FeedURL(URL(string: "https://example.com/notify.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Notify Me"),
      unsavedEpisodes: [try Create.unsavedEpisode(guid: "notify-episode", title: "Episode 1")]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)

    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected notify test podcast to be saved before changing settings" }
    )

    viewModel.notifyNewEpisodes = true

    try await Wait.until(
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return savedSeries?.podcast.notifyNewEpisodes == true
          && viewModel.notifyNewEpisodes
          && self.notificationCenter.requestAuthorizationCalls.count == 1
      },
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return """
          Expected notifyNewEpisodes to persist and request authorization.
          repo value: \(String(describing: savedSeries?.podcast.notifyNewEpisodes))
          view model value: \(viewModel.notifyNewEpisodes)
          authorization calls: \(self.notificationCenter.requestAuthorizationCalls.count)
          """
      }
    )

    #expect(notificationCenter.requestAuthorizationCalls.first == [.alert, .sound, .badge])
  }

  private func insertSeriesFromFeed(assetName: String, feedURL: FeedURL) async throws
    -> PodcastSeries
  {
    let data = PreviewBundle.loadAsset(named: assetName, in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: data)
    let podcastFeed = try await PodcastFeed.parse(data, from: feedURL)
    return try await repo.insertSeries(podcastFeed.toUnsavedSeries())
  }

  private func fetchListablePodcast(_ podcastID: Podcast.ID) async throws -> ListablePodcast {
    let results: [PodcastWithEpisodeMetadata<ListablePodcast>] =
      try await observatory.listablePodcastsWithEpisodeMetadata(
        { $0.filter(Podcast.Columns.id == podcastID) },
        limit: 1
      )
      .get()

    return try #require(results.first?.podcast)
  }

  private func searchResultFeedURL() -> FeedURL {
    FeedURL(URL(string: "https://example.com/search-result.rss")!)
  }

  private func select(_ viewModel: PodcastDetailViewModel, episodeIDs: [Episode.ID]) throws {
    for episodeID in episodeIDs {
      let entry = try #require(viewModel.episodeList.allEntries.first { $0.episodeID == episodeID })
      viewModel.episodeList.isSelected[entry.id] = true
    }
  }

  // Saved podcast detail intentionally filters by row title and parent podcast
  // title only. Episode.description stays outside the slim row so detail-list
  // hydration does not widen every saved detail read; adding description search
  // needs a deliberate alternate path rather than piggybacking on the row model.
  @Test(
    "saved podcast detail intentionally filters by episode and podcast title only"
  )
  func savedDetailFilterIsIntentionallyTitleOnly() async throws {
    let descriptionToken = "rutabaga-flagstone-3471"
    let titleToken = "tangerine-dropper"
    let podcastTitleToken = "kaleidoscope-cassette"
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          title: "Detail Search \(podcastTitleToken)",
          description: "Series-level blurb without any of the tokens"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "title-match",
            title: "Episode \(titleToken)",
            description: "intro with no special tokens"
          ),
          try Create.unsavedEpisode(
            guid: "description-only",
            title: "Episode With Plain Title",
            description: "intro that mentions \(descriptionToken)"
          ),
        ]
      )
    )
    let titleMatchID = savedSeries.episodes[0].id
    let descriptionOnlyID = savedSeries.episodes[1].id

    let viewModel = PodcastDetailViewModel(
      podcast: DisplayedPodcast(savedSeries.podcast)
    )
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected both saved episodes to load before filtering; got \(viewModel.episodeList.allEntries.count)"
      }
    )

    // Drop the debounce so each search term applies immediately.
    viewModel.episodeList.debounceDuration = .zero

    // Episode title token matches just the first row.
    viewModel.episodeList.entryFilter = titleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.episodeID) == [titleMatchID]
      },
      { @MainActor in
        """
        Expected episode-title token '\(titleToken)' to match the first row.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Podcast title token matches every row (both share the parent podcast).
    viewModel.episodeList.entryFilter = podcastTitleToken
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == 2
      },
      { @MainActor in
        """
        Expected podcast-title token '\(podcastTitleToken)' to match both rows.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )

    // Description-only token must NOT match under this title-only contract.
    viewModel.episodeList.entryFilter = descriptionToken
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.isEmpty },
      { @MainActor in
        """
        Expected description-only token '\(descriptionToken)' to filter to nothing on saved detail.
        If this test fails because filteredEntries now contains \(descriptionOnlyID), saved detail description search has been reintroduced. Make that product change explicit and keep it off the slim row model unless the query cost is acceptable.
        filteredEntries: \(viewModel.episodeList.filteredEntries.map { ($0.title, $0.episodeID) })
        """
      }
    )
  }

  @Test("podcastSeries observation prunes episodes that have been removed from the DB")
  func podcastSeriesObservationPrunesRemovedEpisodes() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Prune Test"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "keep-1"),
          try Create.unsavedEpisode(guid: "remove-me"),
          try Create.unsavedEpisode(guid: "keep-2"),
        ]
      )
    )
    let removedID = savedSeries.episodes[1].id

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()
    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 3 },
      { @MainActor in
        "Expected 3 entries after initial observation; got \(viewModel.episodeList.allEntries.count)"
      }
    )

    _ = try await appDB.db.write { db in
      try Episode.deleteOne(db, key: removedID)
    }

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.count == 2
          && viewModel.episodeList.allEntries.allSatisfy { $0.episodeID != removedID }
      },
      { @MainActor in
        """
        Expected the removed episode to be pruned from allEntries.
        count: \(viewModel.episodeList.allEntries.count)
        episodeIDs: \(viewModel.episodeList.allEntries.map(\.episodeID))
        """
      }
    )
  }
}
