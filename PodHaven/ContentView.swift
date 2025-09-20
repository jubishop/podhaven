// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppLabel.settings.text,
        systemImage: AppLabel.settings.systemImageName,
        value: .settings
      ) {
        TabContentWithPlayBar { SettingsView() }
      }
      Tab(
        AppLabel.search.text,
        systemImage: AppLabel.search.systemImageName,
        value: .search,
        role: .search
      ) {
        TabContentWithPlayBar { SearchView() }
      }
      Tab(
        AppLabel.upNext.text,
        systemImage: AppLabel.upNext.systemImageName,
        value: .upNext
      ) {
        TabContentWithPlayBar { UpNextView() }
      }
      Tab(
        AppLabel.episodes.text,
        systemImage: AppLabel.episodes.systemImageName,
        value: .episodes
      ) {
        TabContentWithPlayBar { EpisodesView() }
      }
      Tab(
        AppLabel.podcasts.text,
        systemImage: AppLabel.podcasts.systemImageName,
        value: .podcasts
      ) {
        TabContentWithPlayBar { PodcastsView() }
      }
    }
  }
}

#if DEBUG
#Preview {
  ContentView()
    .preview()
}
#endif
