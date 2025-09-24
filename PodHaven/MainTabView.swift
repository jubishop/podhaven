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
        AppIcon.settings.text,
        systemImage: AppIcon.settings.systemImageName,
        value: .settings
      ) {
        tabContent { SettingsView() }
      }
      Tab(
        AppIcon.search.text,
        systemImage: AppIcon.search.systemImageName,
        value: .search,
        role: .search
      ) {
        tabContent { SearchView() }
      }
      Tab(
        AppIcon.upNext.text,
        systemImage: AppIcon.upNext.systemImageName,
        value: .upNext
      ) {
        tabContent { UpNextView() }
      }
      Tab(
        AppIcon.episodes.text,
        systemImage: AppIcon.episodes.systemImageName,
        value: .episodes
      ) {
        tabContent { EpisodesView() }
      }
      Tab(
        AppIcon.podcasts.text,
        systemImage: AppIcon.podcasts.systemImageName,
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
