// Copyright Justin Bishop, 2025

import Factory
import Foundation
import SwiftUI

struct PreviewModifier: ViewModifier {
  @State private var alert = Container.shared.alert()

  func body(content: Content) -> some View {
    content
      .customAlert($alert.config)
      .environment(alert)
      .task {}
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
