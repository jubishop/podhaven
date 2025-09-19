#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging
import SwiftUI

struct PreviewModifier: ViewModifier {
  @InjectedObservable(\.alert) private var alert
  @InjectedObservable(\.sheet) private var sheet
  @DynamicInjected(\.playManager) private var playManager

  init() {
    guard Function.neverCalled("previewInit") else { return }

    AppInfo.environment = .preview
    LoggingSystem.bootstrap(PrintLogHandler.init)
  }

  func body(content: Content) -> some View {
    content
      .customAlert($alert.config)
      .customSheet($sheet.config)
      .task {
        guard Function.neverCalled("previewTask") else { return }

        await playManager.start()
      }
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
#endif
