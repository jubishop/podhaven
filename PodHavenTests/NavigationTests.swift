// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Sharing
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Navigation tests", .container)
@MainActor class NavigationTests {
  @DynamicInjected(\.navigation) private var navigation

  @ObservationIgnored @Shared(.appStorage("navigationEpisodesTopDestination"))
  private var topEpisodeDestination: Navigation.EpisodesViewType?

  @ObservationIgnored @Shared(.appStorage("navigationPodcastsTopDestination"))
  private var topPodcastDestination: Navigation.PodcastsViewType?

  @Test("that showEpisodes sets current tab and appends to episodes path")
  func showEpisodesNavigatesToCorrectTab() async throws {
    navigation.showEpisodes(.finished)

    #expect(navigation.currentTab == .episodes, "Current tab should be episodes")
    #expect(navigation.episodes.path == [.episodesViewType(.finished)])
  }

  @Test("that showPodcast sets current tab and appends to podcasts path")
  func showPodcastNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let podcast = podcastEpisode.podcast

    navigation.showPodcast(podcast)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.unsubscribed), .podcast(DisplayedPodcast(podcast)),
      ]
    )
  }

  @Test("that showEpisode sets current tab and appends to podcasts path")
  func showEpisodeNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: Create.unsavedPodcast(subscriptionDate: Date()),
        unsavedEpisode: Create.unsavedEpisode()
      )
    )

    navigation.showEpisode(podcastEpisode)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(
      navigation.podcasts.path == [
        .podcastsViewType(.subscribed), .podcast(DisplayedPodcast(podcastEpisode.podcast)),
        .episode(DisplayedEpisode(podcastEpisode)),
      ]
    )
  }

  @Test("episodes tab restores stored top destination on activation")
  func episodesTabRestoresStoredDestination() async throws {
    $topEpisodeDestination.withLock { $0 = .cached }

    #expect(navigation.episodes.path == [.episodesViewType(.cached)])
  }

  @Test("podcasts tab restores stored top destination on activation")
  func podcastsTabRestoresStoredDestination() async throws {
    $topPodcastDestination.withLock { $0 = .subscribed }

    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])
  }
}
