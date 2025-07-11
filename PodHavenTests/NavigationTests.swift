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

  @Test("that showPlaylist sets current tab and appends to playlists path")
  func showPlaylistNavigatesToCorrectTab() async throws {
    navigation.showPlaylist(.completed)

    #expect(navigation.currentTab == .playlists, "Current tab should be playlists")
    #expect(navigation.playlists.path.count == 1, "Playlists path should have one item")
    #expect(
      navigation.playlists.path.first == .viewType(.completed),
      "Playlists path should contain completed viewType"
    )
  }

  @Test("that showPodcast sets current tab and appends to podcasts path")
  func showPodcastNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let podcast = podcastEpisode.podcast

    navigation.showPodcast(.all, podcast)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(navigation.podcasts.path.count == 2, "Podcasts path should have two items")
    #expect(
      navigation.podcasts.path[0] == .viewType(.all),
      "First path item should be viewType(.all)"
    )
    #expect(
      navigation.podcasts.path[1] == .podcast(podcast),
      "Second path item should be podcast"
    )
  }

  @Test("that showEpisode sets current tab and appends to podcasts path")
  func showEpisodeNavigatesToCorrectTab() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    navigation.showEpisode(.subscribed, podcastEpisode)

    #expect(navigation.currentTab == .podcasts, "Current tab should be podcasts")
    #expect(navigation.podcasts.path.count == 3, "Podcasts path should have three items")
    #expect(
      navigation.podcasts.path[0] == .viewType(.subscribed),
      "First path item should be viewType(.subscribed)"
    )
    #expect(
      navigation.podcasts.path[1] == .podcast(podcastEpisode.podcast),
      "Second path item should be podcast"
    )
    #expect(
      navigation.podcasts.path[2] == .episode(podcastEpisode),
      "Third path item should be episode"
    )
  }

  @Test("that changing tabs clears navigation paths")
  func changingTabsClearsNavigationPaths() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Set up some navigation state
    navigation.showPodcast(.all, podcastEpisode.podcast)
    navigation.showPlaylist(.completed)

    // Verify initial state
    #expect(navigation.currentTab == .playlists, "Current tab should be playlists")
    #expect(navigation.playlists.path.count == 1, "Playlists path should have one item")

    // Change to a different tab
    navigation.currentTab = .settings

    // Verify paths are cleared
    #expect(navigation.playlists.path.isEmpty, "Playlists path should be empty")
    #expect(navigation.podcasts.path.isEmpty, "Podcasts path should be empty")
    #expect(navigation.settings.path.isEmpty, "Settings path should be empty")
  }
}
