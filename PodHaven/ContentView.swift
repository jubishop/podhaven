// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

struct ContentView: View {
  @State private var navigation = Container.shared.navigation()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        SettingsView().tab()
      }
      Tab("Up Next", systemImage: "list.bullet", value: .upNext) {
        UpNextView().tab()
      }
      Tab("Discover", systemImage: "magnifyingglass", value: .discover, role: .search) {
        DiscoverView().tab()
      }
      Tab("Podcasts", systemImage: "dot.radiowaves.left.and.right", value: .podcasts) {
        PodcastsView().tab()
      }
    }
    .overlay(alignment: .bottom) {
      if PlayState.shared.playbarVisible {
        PlayBar()
          .padding(.bottom, 50)
      }
    }
  }
}

#Preview {
  ContentView().preview()
}
