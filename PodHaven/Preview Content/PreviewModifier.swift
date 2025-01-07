// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

struct PreviewModifier: ViewModifier {
  @State private var alert = Alert.shared

  func body(content: Content) -> some View {
    content.customAlert($alert.config)
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
