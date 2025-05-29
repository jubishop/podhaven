// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

extension Container {
  @MainActor var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.cached)
  }
}

@Observable @MainActor class Navigation {
  enum Tab {
    case settings, search, upNext, playlists, podcasts
  }

  enum SettingsView {
    case opml
  }

  enum PodcastsView {
    case all
    case subscribed
    case unsubscribed
  }

  enum PlaylistsView {
    case completed, unfinished
  }

  var settingsPath = NavigationPath()
  var searchPath = NavigationPath()
  var upNextPath = NavigationPath()
  var playlistsPath = NavigationPath()
  var podcastsPath = NavigationPath()
  var currentTab: Tab = .settings {
    willSet {
      clearPaths(newValue)
    }
  }

  func showPlaylist(_ view: PlaylistsView) {
    currentTab = .playlists
    playlistsPath.append(view)
  }

  func showPodcast(_ view: PodcastsView, _ podcastSeries: PodcastSeries) {
    currentTab = .podcasts
    podcastsPath.append(view)
    podcastsPath.append(podcastSeries.podcast)
  }

  func showEpisode(_ view: PodcastsView, _ podcastEpisode: PodcastEpisode) {
    currentTab = .podcasts
    podcastsPath.append(view)
    podcastsPath.append(podcastEpisode.podcast)
    podcastsPath.append(podcastEpisode.episode)
  }

  fileprivate init() {}

  private func clearPaths(_ tab: Tab) {
    switch tab {
    case .settings:
      settingsPath = NavigationPath()
    case .search:
      searchPath = NavigationPath()
    case .upNext:
      upNextPath = NavigationPath()
    case .playlists:
      playlistsPath = NavigationPath()
    case .podcasts:
      podcastsPath = NavigationPath()
    }
  }
}
