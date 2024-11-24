// Copyright Justin Bishop, 2024

import SwiftUI

struct ContentView: View {
  @State private var navigation: Navigation = Navigation()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        SettingsView()
      }
      Tab("Up Next", systemImage: "music.note.list", value: .upNext) {
        Button("Go to settings") {
          navigation.currentTab = .settings
        }
      }
    }
    .environment(navigation)
  }
}

#Preview {
  ContentView()
}
