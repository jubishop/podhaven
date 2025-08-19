// Copyright Justin Bishop, 2025

import SwiftUI

struct ConditionalRefreshableViewModifier: ViewModifier {
  let enabled: Bool
  let action: () async -> Void

  func body(content: Content) -> some View {
    if enabled {
      content.refreshable { await action() }
    } else {
      content
    }
  }
}

extension View {
  func conditionalRefreshable(
    enabled: Bool,
    action: @escaping () async -> Void
  ) -> some View {
    self.modifier(ConditionalRefreshableViewModifier(enabled: enabled, action: action))
  }
}
