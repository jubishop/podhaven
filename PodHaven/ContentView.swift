// Copyright Justin Bishop, 2024

import SwiftUI

struct ContentView: View {
  @State private var navigation = Navigation.shared
  @State private var fullStackHeight: CGFloat = 0
  @State private var tabHeights: [Navigation.Tab: CGFloat] = [:]

  var body: some View {
    ZStack(alignment: .bottom) {
      TabView(selection: $navigation.currentTab) {
        Tab(
          "Settings",
          systemImage: "gear",
          value: .settings
        ) {
          TabContent(height: tabHeightsBinding(for: .settings)) {
            SettingsView()
          }
        }
        Tab(
          "Podcasts",
          systemImage: "dot.radiowaves.left.and.right",
          value: .podcasts
        ) {
          TabContent(height: tabHeightsBinding(for: .podcasts)) {
            PodcastsView()
          }
        }
      }
      PlayBar()
        .offset(
          y: tabHeights[navigation.currentTab, default: 0] - fullStackHeight
        )
    }
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.size.height
    } action: { newHeight in
      fullStackHeight = newHeight
    }
  }

  private func tabHeightsBinding(for tab: Navigation.Tab) -> Binding<CGFloat> {
    Binding(
      get: { tabHeights[tab, default: 0] },
      set: { tabHeights[tab] = $0 }
    )
  }
}

#Preview {
  Preview { ContentView() }
}
