// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import SwiftUI

struct PreviewModifier: ViewModifier {
  private static var isInitialized: Bool = false

  @InjectedObservable(\.alert) private var alert

  init() {
    if !Self.isInitialized {
      AppInfo.environment = .preview
      PodHavenApp.configureLogging()
      Self.isInitialized = true
    }
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
