// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct NavStack<Manager, Content>: View
where Manager: Navigation.ManagingPath, Content: View {
  @DynamicInjected(\.navigation) private var navigation

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
  }
}
