// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Navigation tests", .container)
@MainActor class NavigationTests {
  @DynamicInjected(\.navigation) private var navigation

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

  @Test("episodes tab saves top destination when path changes")
  func episodesTabSavesTopDestination() async throws {
    navigation.showEpisodes(.cached)
    #expect(navigation.episodes.path == [.episodesViewType(.cached)])

    navigation.showEpisodes(.finished)
    #expect(navigation.episodes.path == [.episodesViewType(.finished)])
  }

  @Test("podcasts tab saves top destination when path changes")
  func podcastsTabSavesTopDestination() async throws {
    navigation.showPodcastList(.subscribed)
    #expect(navigation.podcasts.path == [.podcastsViewType(.subscribed)])

    navigation.showPodcastList(.unsubscribed)
    #expect(navigation.podcasts.path == [.podcastsViewType(.unsubscribed)])
  }

  @Test("clearing episodes path resets top destination")
  func clearingEpisodesPathResetsTopDestination() async throws {
    navigation.showEpisodes(.cached)
    #expect(navigation.episodes.path.count == 1)

    navigation.episodes.path = []
    #expect(navigation.episodes.path.isEmpty)
  }

  @Test("clearing podcasts path resets top destination")
  func clearingPodcastsPathResetsTopDestination() async throws {
    navigation.showPodcastList(.subscribed)
    #expect(navigation.podcasts.path.count == 1)

    navigation.podcasts.path = []
    #expect(navigation.podcasts.path.isEmpty)
  }
}
