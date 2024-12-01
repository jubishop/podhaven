// Copyright Justin Bishop, 2024

import SwiftUI

struct ContentView: View {
  @State private var navigation: Navigation = Navigation()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        SettingsView()
      }
      Tab(
        "Podcasts",
        systemImage: "dot.radiowaves.left.and.right",
        value: .podcasts
      ) {
        PodcastsView()
      }
    }
    .environment(navigation)
  }
}

#Preview {
  ContentView()
}
