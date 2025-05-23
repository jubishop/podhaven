// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct PreviewModifier: ViewModifier {
  @InjectedObservable(\.alert) private var alert

  func body(content: Content) -> some View {
    content
      .customAlert($alert.config)
      .task {}
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
