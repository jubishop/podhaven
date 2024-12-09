// Copyright Justin Bishop, 2024

import SwiftUI

@Observable @MainActor
final class TabHeights: Sendable {
  private var heights: [Navigation.Tab: CGFloat] = [:]

  subscript(tab: Navigation.Tab) -> Binding<CGFloat> {
    get {
      Binding(
        get: { self.heights[tab, default: 0] },
        set: { self.heights[tab] = $0 }
      )
    }
  }
}

struct ContentView: View {
  @State private var navigation = Navigation.shared
  @State private var fullStackHeight: CGFloat = 0
  @State private var tabHeights = TabHeights()

  var body: some View {
    ZStack(alignment: .bottom) {
      TabView(selection: $navigation.currentTab) {
        Tab(
          "Settings",
          systemImage: "gear",
          value: .settings
        ) {
          TabContent(height: tabHeights[.settings]) {
            SettingsView()
          }
        }
        Tab(
          "Podcasts",
          systemImage: "dot.radiowaves.left.and.right",
          value: .podcasts
        ) {
          TabContent(height: tabHeights[.podcasts]) {
            PodcastsView()
          }
        }
      }
      PlayBar()
        .offset(
          y: tabHeights[navigation.currentTab].wrappedValue - fullStackHeight
        )
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
