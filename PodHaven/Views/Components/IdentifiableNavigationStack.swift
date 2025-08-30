// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

/// A NavigationStack wrapper that automatically resets when the ManagingNavigationPaths is cleared.
/// This ensures that when navigation paths are cleared, the NavigationStack
/// properly resets to its root state without retaining stale navigation state.
struct IdentifiableNavigationStack<Manager, Content>: View
where Manager: ManagingNavigationPaths, Content: View {
  @InjectedObservable(\.navigation) private var navigation

  @Bindable var manager: Manager
  let content: () -> Content

  init(
    manager: Manager,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self.manager = manager
    self.content = content
  }

  var body: some View {
    NavigationStack(path: $manager.path) {
      content()
        .navigationDestination(
          for: Navigation.Destination.self,
          destination: navigation.navigationDestination
        )
    }
    .id(manager.resetId)
  }
}
