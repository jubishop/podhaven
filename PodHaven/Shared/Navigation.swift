// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

extension Container {
  var navigation: Factory<Navigation> {
    Factory(self) { @MainActor in Navigation() }.scope(.singleton)
  }
}

@Observable @MainActor final class Navigation: Sendable {
  enum Tab {
    case settings, podcasts, upNext, discover
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

  func showTab(_ tab: Tab) {
    clearPaths(tab)
    currentTab = tab
  }

  func showEpisode(_ podcastEpisode: PodcastEpisode) {
    showTab(.podcasts)
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
