// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct ContentView: View {
  @State private var navigation = Container.shared.navigation()
  @State private var playState = Container.shared.playState()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        SettingsView().tab()
      }
      Tab("Playlists", systemImage: "list.bullet", value: .playlists) {
        PlaylistsView().tab()
      }
      Tab("Discover", systemImage: "magnifyingglass", value: .discover, role: .search) {
        DiscoverView().tab()
      }
      Tab("Podcasts", systemImage: "dot.radiowaves.left.and.right", value: .podcasts) {
        PodcastsView().tab()
      }
    }
    .overlay(alignment: .bottom) {
      if playState.playbarVisible {
        PlayBar()
          .padding(.bottom, 50)
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
