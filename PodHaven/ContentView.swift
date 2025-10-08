// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState
  @InjectedObservable(\.userSettings) private var userSettings

  private static let log = Log.as("ContentView")

  @State private var tabMaxY: CGFloat = 0

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppIcon.upNext.text,
        systemImage: AppIcon.upNext.systemImageName,
        value: .upNext
      ) {
        UpNextView(viewModel: UpNextViewModel())
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
        AppIcon.settings.text,
        systemImage: AppIcon.settings.systemImageName,
        value: .settings
      ) {
        SettingsView()
      }
      Tab(
        AppIcon.search.text,
        systemImage: AppIcon.search.systemImageName,
        value: .search,
        role: .search
      ) {
        SearchView(viewModel: SearchViewModel())
      }
    }
    .coordinateSpace(name: PlayBarAccessory.CoordinateName)
    .onGeometryChange(for: CGFloat.self) { geometry in
      geometry.frame(in: .named(PlayBarAccessory.CoordinateName)).maxY
    } action: { newMaxY in
      Self.log.trace("New maxY: \(newMaxY)")
      tabMaxY = newMaxY
    }
    .tabBarMinimizeBehavior(userSettings.shrinkPlayBarOnScroll ? .onScrollDown : .never)
    .tabViewBottomAccessory {
      PlayBarAccessory(tabMaxY: tabMaxY)
    }
  }
}
