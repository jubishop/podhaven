// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("PodcastDetailViewModel tests", .container)
@MainActor final class PodcastDetailViewModelTests {
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
}
