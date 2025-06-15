// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

struct PreviewModifier: ViewModifier {
  @InjectedObservable(\.alert) private var alert

  init() {
    guard Function.neverCalled() else { return }

    AppInfo.environment = .preview
    LoggingSystem.bootstrap(PrintLogHandler.init)
  }

  func body(content: Content) -> some View {
    content
      .customAlert($alert.config)
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
