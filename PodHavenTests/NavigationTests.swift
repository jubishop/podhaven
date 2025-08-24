// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of Navigation tests", .container)
@MainActor class NavigationTests {
  @DynamicInjected(\.navigation) private var navigation

  @Test("that showEpisodes sets current tab and appends to episodes path")
  func showEpisodesNavigatesToCorrectTab() async throws {
    navigation.showEpisodes(.completed)

    #expect(navigation.currentTab == .episodes, "Current tab should be episodes")
    #expect(navigation.episodes.path == [.viewType(.completed)])
  }

  @Test("that showPodcast sets current tab and appends to podcasts path")
  func showPodcastNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let podcast = podcastEpisode.podcast

    navigation.showPodcast(.subscribed, podcast)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(navigation.podcasts.path == [.viewType(.subscribed), .podcast(podcast)])
  }

  @Test("that showEpisode sets current tab and appends to podcasts path")
  func showEpisodeNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    navigation.showEpisode(.subscribed, podcastEpisode)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(
      navigation.podcasts.path == [
        .viewType(.subscribed), .podcast(podcastEpisode.podcast), .episode(podcastEpisode),
      ]
    )
  }

  @Test("that changing tabs clears upcoming navigation path")
  func changingTabsClearsUpcomingNavigationPath() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Set up some navigation state
    navigation.showPodcast(.subscribed, podcastEpisode.podcast)
    navigation.showEpisodes(.completed)

    // Verify initial state
    #expect(navigation.currentTab == .episodes, "Current tab should be episodes")
    #expect(!navigation.episodes.path.isEmpty)

    // Change to a different tab
    navigation.currentTab = .settings

    // Verify path is cleared
    #expect(navigation.settings.path.isEmpty, "Settings path should be empty")
  }
}
