// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as("ContentView")

  @State private var playBarViewModel = PlayBarViewModel()

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppIcon.upNext.textKey,
        systemImage: AppIcon.upNext.systemImageName,
        value: .upNext
      ) {
        UpNextView(viewModel: UpNextViewModel())
      }
      Tab(
        AppIcon.episodes.textKey,
        systemImage: AppIcon.episodes.systemImageName,
        value: .episodes
      ) {
        EpisodesView()
      }
      Tab(
        AppIcon.podcasts.textKey,
        systemImage: AppIcon.podcasts.systemImageName,
        value: .podcasts
      ) {
        PodcastsView()
      }
      Tab(
        AppIcon.settings.textKey,
        systemImage: AppIcon.settings.systemImageName,
        value: .settings
      ) {
        SettingsView()
      }
      Tab(
        AppIcon.search.textKey,
        systemImage: AppIcon.search.systemImageName,
        value: .search,
        role: .search
      ) {
        SearchView(viewModel: SearchViewModel())
      }
    }
    .tabBarMinimizeBehavior(userSettings.shrinkPlayBarOnScroll ? .onScrollDown : .never)
    .tabViewBottomAccessory {
      PlayBar(viewModel: playBarViewModel)
    }
    .sheet(isPresented: $playBarViewModel.playBarSheetIsPresented) {
      PlayBarSheet(viewModel: playBarViewModel)
    }
  }
}
