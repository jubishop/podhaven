// Copyright Justin Bishop, 2024

import SwiftUI

struct ContentView: View {
  @State private var navigation = Navigation.shared
  @State private var fullStackHeight: CGFloat = 0
  @State private var tabHeights = BindableDictionary<Navigation.Tab, CGFloat>(defaultValue: 0)

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab("Settings", systemImage: "gear", value: .settings) {
        TabContentWrapper(height: $tabHeights[.settings]) {
          SettingsView()
        }
      }
      Tab("Up Next", systemImage: "list.bullet", value: .upNext) {
        TabContentWrapper(height: $tabHeights[.upNext]) {
          UpNextView()
        }
      }
      Tab("Discover", systemImage: "magnifyingglass", value: .discover, role: .search) {
        TabContentWrapper(height: $tabHeights[.discover]) {
          DiscoverView()
        }
      }
      Tab("Podcasts", systemImage: "dot.radiowaves.left.and.right", value: .podcasts) {
        TabContentWrapper(height: $tabHeights[.podcasts]) {
          PodcastsView()
        }
      }
    }
    .overlay(alignment: .bottom) {
      PlayBar()
        .offset(y: tabHeights[navigation.currentTab] - fullStackHeight)
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
