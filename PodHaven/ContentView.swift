// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState

  @State private var tabMaxY: CGFloat = 0

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppIcon.settings.text,
        systemImage: AppIcon.settings.systemImageName,
        value: .settings
      ) {
        SettingsView()
      }
      Tab(
        AppIcon.upNext.text,
        systemImage: AppIcon.upNext.systemImageName,
        value: .upNext
      ) {
        UpNextView()
      }
      Tab(
        AppIcon.episodes.text,
        systemImage: AppIcon.episodes.systemImageName,
        value: .episodes
      ) {
        EpisodesView()
      }
      Tab(
        AppIcon.podcasts.text,
        systemImage: AppIcon.podcasts.systemImageName,
        value: .podcasts
      ) {
        PodcastsView()
      }
      Tab(
        AppIcon.search.text,
        systemImage: AppIcon.search.systemImageName,
        value: .search,
        role: .search
      ) {
        SearchView()
      }
    }
    .coordinateSpace(name: PlayBarAccessory.CoordinateName)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.frame(in: .named(PlayBarAccessory.CoordinateName)).maxY
    } action: { newMaxY in
      tabMaxY = newMaxY
    }
    .tabBarMinimizeBehavior(.onScrollDown)
    .tabViewBottomAccessory {
      PlayBarAccessory(tabMaxY: tabMaxY)
    }
  }
}

#if DEBUG
#Preview {
  ContentView()
    .preview()
}
#endif
