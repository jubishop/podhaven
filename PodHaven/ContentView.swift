// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @State private var navigation = Container.shared.navigation()
  @State private var playState = Container.shared.playState()

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
      Tab("Playlists", systemImage: "list.bullet", value: .playlists) {
        TabContentWithPlayBar { PlaylistsView() }
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
