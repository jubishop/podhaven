// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct MainTabView: View {
  @InjectedObservable(\.navigation) private var navigation

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppLabel.settings.text,
        systemImage: AppLabel.settings.systemImageName,
        value: .settings
      ) {
        SettingsView()
      }
      Tab(
        AppLabel.search.text,
        systemImage: AppLabel.search.systemImageName,
        value: .search,
        role: .search
      ) {
        SearchView()
      }
      Tab(
        AppLabel.upNext.text,
        systemImage: AppLabel.upNext.systemImageName,
        value: .upNext
      ) {
        UpNextView()
      }
      Tab(
        AppLabel.episodes.text,
        systemImage: AppLabel.episodes.systemImageName,
        value: .episodes
      ) {
        EpisodesView()
      }
      Tab(
        AppLabel.podcasts.text,
        systemImage: AppLabel.podcasts.systemImageName,
        value: .podcasts
      ) {
        PodcastsView()
      }
    }
  }
}
