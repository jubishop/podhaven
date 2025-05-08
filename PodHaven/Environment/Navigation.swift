// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

extension Container {
  var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.cached)
  }
}

@Observable @MainActor final class Navigation: Sendable {
  enum Tab {
    case settings, podcasts, upNext, discover
  }

  enum SettingsView {
    case opml
  }

  enum PodcastsView {
    case all
    case subscribed
    case unsubscribed
  }

  var settingsPath = NavigationPath()
  var podcastsPath = NavigationPath()
  var upNextPath = NavigationPath()
  var discoverPath = NavigationPath()
  var currentTab: Tab = .settings {
    willSet {
      clearPaths(newValue)
    }
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
    case .podcasts:
      podcastsPath = NavigationPath()
    case .upNext:
      upNextPath = NavigationPath()
    case .discover:
      discoverPath = NavigationPath()
    }
  }
}
