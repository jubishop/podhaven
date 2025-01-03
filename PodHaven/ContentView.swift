// Copyright Justin Bishop, 2024

import SwiftUI

struct ContentView: View {
  @State private var navigation = Navigation.shared
  @State private var fullStackHeight: CGFloat = 0
  @State private var internalHeight: CGFloat = 0

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        SettingsView()
          .tab()
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
          } action: { newHeight in
            internalHeight = newHeight
          }
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
      PlayBar()
        .padding(.bottom, fullStackHeight - internalHeight)
    }
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.height
    } action: { newHeight in
      fullStackHeight = newHeight
    }
  }
}

#Preview {
  Preview { ContentView() }
}
