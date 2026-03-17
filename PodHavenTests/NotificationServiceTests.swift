// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of NotificationService tests", .container)
@MainActor class NotificationServiceTests {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.notificationService) private var notificationService
  @DynamicInjected(\.repo) private var repo

  // MARK: - URL Analysis

  @Test("isNotificationURL returns true for notification host")
  func isNotificationURLReturnsTrue() throws {
    let url = try #require(URL(string: "podhaven://notification/episode/123"))
    #expect(NotificationService.isNotificationURL(url))
  }

  @Test("isNotificationURL returns false for other hosts")
  func isNotificationURLReturnsFalse() throws {
    let url = try #require(URL(string: "podhaven://widget/queue/123"))
    #expect(!NotificationService.isNotificationURL(url))
  }

  // MARK: - Episode Deep Link

  @Test(
    "episode URL navigates to episode detail",
    arguments: [false, true]
  )
  func episodeURLNavigatesToEpisode(subscribed: Bool) async throws {
    var podcastEpisode = try await Create.podcastEpisode()
    if subscribed {
      try await repo.markSubscribed(podcastEpisode.podcast.id)
    }
    podcastEpisode = try await repo.podcastEpisode(podcastEpisode.episode.id)!

    let url = try #require(
      URL(string: NotificationService.episodeURL(podcastEpisode.episode.id))
    )

    await notificationService.handleIncomingURL(url)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(subscribed ? .subscribed : .unsubscribed),
        .podcast(DisplayedPodcast(podcastEpisode.podcast)),
        .episode(DisplayedEpisode(podcastEpisode)),
      ]
    )
  }

  @Test("episode URL with unknown ID falls back to podcast list")
  func episodeURLWithUnknownIDFallsBackToPodcastList() async throws {
    let url = try #require(URL(string: "podhaven://notification/episode/99999"))

    await notificationService.handleIncomingURL(url)

    #expect(navigation.currentTab == .podcasts)
    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])
  }

  // MARK: - Podcast Deep Link

  @Test(
    "podcast URL navigates to podcast detail",
    arguments: [false, true]
  )
  func podcastURLNavigatesToPodcast(subscribed: Bool) async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    if subscribed {
      try await repo.markSubscribed(podcastEpisode.podcast.id)
    }
    let podcastSeries = try await repo.podcastSeries(podcastEpisode.podcast.id)!

    let url = try #require(
      URL(string: NotificationService.podcastURL(podcastSeries.podcast.id))
    )

    await notificationService.handleIncomingURL(url)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(subscribed ? .subscribed : .unsubscribed),
        .podcast(DisplayedPodcast(podcastSeries.podcast)),
      ]
    )
  }

  @Test("podcast URL with unknown ID falls back to podcast list")
  func podcastURLWithUnknownIDFallsBackToPodcastList() async throws {
    let url = try #require(URL(string: "podhaven://notification/podcast/99999"))

    await notificationService.handleIncomingURL(url)

    #expect(navigation.currentTab == .podcasts)
    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])
  }

  // MARK: - Unknown Path

  @Test("unknown path does not navigate")
  func unknownPathDoesNotNavigate() async throws {
    let url = try #require(URL(string: "podhaven://notification/unknown/123"))

    await notificationService.handleIncomingURL(url)

    #expect(navigation.currentTab == .upNext)
    #expect(navigation.podcasts.path.isEmpty)
  }
}
