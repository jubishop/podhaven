// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel subscribe tests", .container)
@MainActor final class SubscribeTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.userNotificationCenter) private var userNotificationCenter

  private var notificationCenter: FakeUserNotificationCenter {
    userNotificationCenter as! FakeUserNotificationCenter
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

  @Test("subscribe from a saved-listed initial state marks the existing series subscribed")
  func subscribeFromInitialListedStateMarksSavedSeriesSubscribed() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/initial-subscribe.rss")!)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Initial Subscribe"),
        unsavedEpisodes: [try Create.unsavedEpisode(guid: "init-sub-ep", title: "Episode 1")]
      )
    )
    // Inserted series defaults to unsubscribed; verify before tapping.
    let preSeries = try #require(try await repo.podcastSeries(savedSeries.id))
    #expect(preSeries.podcast.subscribed == false)

    let listablePodcast = try await PodcastDetailTestHelpers.fetchListablePodcast(savedSeries.id)
    let viewModel = PodcastDetailViewModel(listedPodcast: ListedPodcast(saved: listablePodcast))
    // .initial state — saved series not yet hydrated by performAppear.
    #expect(viewModel.saved == false)

    viewModel.subscribe()

    try await Wait.until(
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return viewModel.saved
          && viewModel.podcast.subscribed
          && series?.podcast.subscribed == true
      },
      { @MainActor in
        let series = try await self.repo.podcastSeries(savedSeries.id)
        return """
          Expected subscribe() from .initial(listedPodcast) to mark the saved series subscribed.
          viewModel.saved: \(viewModel.saved)
          viewModel.podcast.subscribed: \(viewModel.podcast.subscribed)
          series.podcast.subscribed: \(String(describing: series?.podcast.subscribed))
          """
      }
    )
  }

  @Test("subscribe preserves the unsaved episode list across the saved-bootstrap window")
  func subscribePreservesEpisodeListAcrossInsertBootstrap() async throws {
    // pubDates intentionally descending: keeps the unsaved insertion order
    // byte-equal to the eventual saved-series fetch order (pubDate desc),
    // so the assertion only catches `episodeList` getting wiped — never a
    // benign reorder from observation.
    let feedURL = FeedURL(URL(string: "https://example.com/bootstrap-subscribe.rss")!)
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, title: "Bootstrap Subscribe"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: "bootstrap-1",
          title: "Episode 1",
          pubDate: Date(timeIntervalSince1970: 300)
        ),
        try Create.unsavedEpisode(
          guid: "bootstrap-2",
          title: "Episode 2",
          pubDate: Date(timeIntervalSince1970: 200)
        ),
        try Create.unsavedEpisode(
          guid: "bootstrap-3",
          title: "Episode 3",
          pubDate: Date(timeIntervalSince1970: 100)
        ),
      ]
    )
    // Stub `podcastSeriesDetail` so the observation the VM starts after
    // insert throws on first iteration. That cuts off the live-hydration
    // path and leaves `.saved(emptyPodcastSeriesDetail)` as the terminal
    // state, so the only thing that can touch `episodeList` is the
    // bootstrap-skip in `refreshEpisodeList`.
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.podcastSeriesDetailScript([
      { _ in
        ValueObservation
          .tracking { _ -> PodcastSeriesDetail? in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.allEntries.map(\.title) == [
          "Episode 1", "Episode 2", "Episode 3",
        ]
      },
      { @MainActor in
        """
        Expected unsaved init to populate episodeList before subscribe.
        titles: \(viewModel.episodeList.allEntries.map(\.title))
        """
      }
    )

    viewModel.subscribe()

    // Wait for the saved transition. With observation stubbed to throw,
    // no further transitions follow, so the only thing that can change
    // episodeList from here is `refreshEpisodeList`'s bootstrap-skip
    // branch. Yield a few times so PowerList's debounced `_allEntries`
    // task drains before the assertion lands.
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.saved },
      { @MainActor in "Expected subscribe() to land in saved state" }
    )
    for _ in 0..<10 { await Task.yield() }
    #expect(
      viewModel.episodeList.allEntries.map(\.title) == [
        "Episode 1", "Episode 2", "Episode 3",
      ]
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

    var newSettings = viewModel.settings ?? .defaults
    newSettings.notifyNewEpisodes = true
    viewModel.updateSettings(newSettings)

    try await Wait.until(
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return savedSeries?.podcast.notifyNewEpisodes == true
          && viewModel.settings?.notifyNewEpisodes == true
          && self.notificationCenter.requestAuthorizationCalls.count == 1
      },
      { @MainActor in
        let savedSeries = try await self.repo.podcastSeries(feedURL)
        return """
          Expected notifyNewEpisodes to persist and request authorization.
          repo value: \(String(describing: savedSeries?.podcast.notifyNewEpisodes))
          view model value: \(String(describing: viewModel.settings?.notifyNewEpisodes))
          authorization calls: \(self.notificationCenter.requestAuthorizationCalls.count)
          """
      }
    )

    #expect(notificationCenter.requestAuthorizationCalls.first == [.alert, .sound, .badge])
  }
}
