// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppIcon.settings.text,
        systemImage: AppIcon.settings.systemImageName,
        value: .settings
      ) {
        SettingsView()
      }
      Tab(
        AppIcon.search.text,
        systemImage: AppIcon.search.systemImageName,
        value: .search,
        role: .search
      ) {
        SearchView()
      }
      Tab(
        AppIcon.upNext.text,
        systemImage: AppIcon.upNext.systemImageName,
        value: .upNext
      ) {
        UpNextView()
      }
      Tab(
        AppIcon.episodes.text,
        systemImage: AppIcon.episodes.systemImageName,
        value: .episodes
      ) {
        EpisodesView()
      }
      Tab(
        AppIcon.podcasts.text,
        systemImage: AppIcon.podcasts.systemImageName,
        value: .podcasts
      ) {
        PodcastsView()
      }
    }
    .tabViewBottomAccessory {
      PlayBar()
    }
  }
}

#if DEBUG
#Preview {
  ContentView()
    .preview()
}
#endif
