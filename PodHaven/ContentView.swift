// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @State private var navigation = Container.shared.navigation()
  @State private var playState = Container.shared.playState()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        TabContentView { SettingsView() }
      }
      Tab("Search", systemImage: "magnifyingglass", value: .search, role: .search) {
        TabContentView { SearchView() }
      }
      Tab(
        "Up Next",
        systemImage: "text.line.first.and.arrowtriangle.forward",
        value: .upNext,
        role: .search
      ) {
        TabContentView { UpNextView() }
      }
      Tab("Playlists", systemImage: "list.bullet", value: .playlists) {
        TabContentView { PlaylistsView() }
      }
      Tab("Podcasts", systemImage: "dot.radiowaves.left.and.right", value: .podcasts) {
        TabContentView { PodcastsView() }
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
