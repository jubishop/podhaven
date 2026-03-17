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

  private static let initializeOnce = Once()
  private static let startOnce = AsyncOnce()

  init() {
    Self.initializeOnce.run {
      Container.shared.registerPreviewDefaults()
      AppInfo.environment = .preview
    }
  }

  func body(content: Content) -> some View {
    content
      .customAlert($alert.config)
      .customSheet($sheet.config)
      .task {
        await Self.startOnce.run {
          await playManager.start()
        }
      }
  }
}

extension View {
  func preview() -> some View {
    self.modifier(PreviewModifier())
  }
}
#endif
