// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        TabContentWithPlayBar { SettingsView() }
      }
      Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
        TabContentWithPlayBar { SearchView() }
      }
      Tab(
        "Up Next",
        systemImage: "text.line.first.and.arrowtriangle.forward",
        value: .upNext,
        role: .search
      ) {
        TabContentWithPlayBar { UpNextView() }
      }
      Tab("Episodes", systemImage: "list.bullet", value: .episodes) {
        TabContentWithPlayBar { EpisodesView() }
      }
      Tab("Podcasts", systemImage: "dot.radiowaves.left.and.right", value: .podcasts) {
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
