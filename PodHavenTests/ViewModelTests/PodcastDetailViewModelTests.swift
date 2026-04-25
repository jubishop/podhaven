// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel tests", .container)
@MainActor final class PodcastDetailViewModelTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.navigation) private var navigation
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
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(listablePodcast))

    #expect(viewModel.isHydratingInitialPresentation)
    #expect(viewModel.shareURL == ShareURL.podcast(feedURL: savedSeries.podcast.feedURL))

    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        !viewModel.isHydratingInitialPresentation
          && viewModel.saved
          && viewModel.podcast.title == savedSeries.podcast.title
          && viewModel.podcast.description == savedSeries.podcast.description
          && viewModel.episodeList.allEntries.count == savedSeries.episodes.count
      },
      { @MainActor in
        """
        Expected list-backed podcast detail to hydrate saved podcast data.
        isHydratingInitialPresentation: \(viewModel.isHydratingInitialPresentation)
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
    let searchResult = SearchResultPodcast(
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
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(searchResult))

    #expect(viewModel.isHydratingInitialPresentation == false)
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
    #expect(viewModel.podcast.getUnsavedPodcast() != nil)
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

    #expect(viewModel.isHydratingInitialPresentation == false)
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
          && viewModel.podcast.getUnsavedPodcast() != nil
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

  @Test("deleting an observed saved series alerts and dismisses when feed recovery fails")
  func observedDeletionFailureAlertsAndDismisses() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/deleted-podcast.rss")!)
    let feedData = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    await feedSession.respond(to: feedURL.rawValue, data: feedData)
    let podcastFeed = try await PodcastFeed.parse(feedData, from: feedURL)
    let savedSeries = try await repo.insertSeries(podcastFeed.toUnsavedSeries())
    let displayedPodcast = DisplayedPodcast(savedSeries.podcast)

    navigation.currentTab = .podcasts
    navigation.podcasts.path = [
      .podcastsViewType(.unsubscribed),
      .podcast(displayedPodcast),
    ]

    let viewModel = PodcastDetailViewModel(podcast: displayedPodcast)

    try await viewModel.performAppear()

    await feedSession.respond(to: feedURL.rawValue, error: URLError(.cannotLoadFromNetwork))
    _ = try await repo.deletePodcast(savedSeries.id)

    try await Wait.until(
      { @MainActor [self] in
        alert.config != nil
          && navigation.podcasts.path == [.podcastsViewType(.unsubscribed)]
      },
      { @MainActor [self] in
        """
        Expected failed feed recovery after deletion to alert and dismiss.
        alert presented: \(alert.config != nil)
        navigation path: \(navigation.podcasts.path)
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
          && viewModel.podcast.notifyNewEpisodes
          && self.notificationCenter.requestAuthorizationCalls.count == 1
      },
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return """
          Expected notifyNewEpisodes to persist and request authorization.
          repo value: \(String(describing: savedSeries?.podcast.notifyNewEpisodes))
          view model value: \(viewModel.podcast.notifyNewEpisodes)
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
}
