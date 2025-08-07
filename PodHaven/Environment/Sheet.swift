// Copyright Justin Bishop, 2025

import FactoryKit
import OSLog
import SwiftUI

extension Container {
  @MainActor var sheet: Factory<Sheet> {
    Factory(self) { @MainActor in Sheet() }.scope(.cached)
  }
}

@Observable @MainActor class Sheet {
  var config: SheetConfig?

  fileprivate init() {}

  // MARK: - Public Sheet Presentation

  func callAsFunction<Content: View>(@ViewBuilder content: @escaping () -> Content) {
    config = SheetConfig(content: content)
  }

  func dismiss() {
    config = nil
  }
}

@Observable @MainActor class SheetConfig {
  let content: AnyView

  init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
    self.content = AnyView(content())
  }
}

extension View {
  func customSheet(_ config: Binding<SheetConfig?>) -> some View {
    sheet(
      isPresented: Binding(
        get: { config.wrappedValue != nil },
        set: { if !$0 { config.wrappedValue = nil } }
      )
    ) {
      config.wrappedValue?.content
    }
  }
}
