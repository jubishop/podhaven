// Copyright Justin Bishop, 2025

import SwiftUI

struct TabViewModifier: ViewModifier {
  func body(content: Content) -> some View {
    content.toolbarBackground(.visible, for: .tabBar)
  }
}

extension View {
  func tab() -> some View {
    self.modifier(TabViewModifier())
  }
}
