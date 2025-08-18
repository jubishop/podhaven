// Copyright Justin Bishop, 2025

import SwiftUI

/// A NavigationStack wrapper that automatically resets when the NavigationPathManager is cleared.
/// This ensures that when navigation paths are cleared, the NavigationStack
/// properly resets to its root state without retaining stale navigation state.
struct IdentifiableNavigationStack<Manager, Content>: View 
where Manager: NavigationPathManager, Content: View {
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
    NavigationStack(path: $manager.path, root: content)
      .id(manager.resetId)
  }
}
