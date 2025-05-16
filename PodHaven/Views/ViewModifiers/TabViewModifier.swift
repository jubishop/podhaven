// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TabViewModifier: ViewModifier {
  @DynamicInjected(\.playBarViewModel) private var playBarViewModel

  func body(content: Content) -> some View {
    content
      .toolbarBackground(.visible, for: .tabBar)
      .padding(.bottom, playBarViewModel.height)
  }
}

extension View {
  func tab() -> some View {
    self.modifier(TabViewModifier())
  }
}
