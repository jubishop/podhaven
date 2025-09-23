// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct MainTabView: View {
  @InjectedObservable(\.navigation) private var navigation

  @Binding var tabContentSafeAreaInset: CGFloat

  init(tabContentSafeAreaInset: Binding<CGFloat>) {
    _tabContentSafeAreaInset = tabContentSafeAreaInset
  }

  var body: some View {
    TabView(selection: $navigation.currentTab) {
      Tab(
        AppLabel.settings.text,
        systemImage: AppLabel.settings.systemImageName,
        value: .settings
      ) {
        tabContent { SettingsView() }
      }
      Tab(
        AppLabel.search.text,
        systemImage: AppLabel.search.systemImageName,
        value: .search,
        role: .search
      ) {
        tabContent { SearchView() }
      }
      Tab(
        AppLabel.upNext.text,
        systemImage: AppLabel.upNext.systemImageName,
        value: .upNext
      ) {
        tabContent { UpNextView() }
      }
      Tab(
        AppLabel.episodes.text,
        systemImage: AppLabel.episodes.systemImageName,
        value: .episodes
      ) {
        tabContent { EpisodesView() }
      }
      Tab(
        AppLabel.podcasts.text,
        systemImage: AppLabel.podcasts.systemImageName,
        value: .podcasts
      ) {
        tabContent { PodcastsView() }
      }
    }
  }

  @ViewBuilder
  private func tabContent<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    content()
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.safeAreaInsets.bottom
      } action: { newInset in
        guard newInset > 0 else { return }
        tabContentSafeAreaInset = newInset
      }
  }
}
