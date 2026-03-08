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

  func callAsFunction<Content: View>(
    id: AnyHashable? = nil,
    @ViewBuilder content: @escaping () -> Content
  ) {
    if let id, config?.id == id { return }
    config = SheetConfig(id: id, content: content)
  }

  func dismiss() {
    config = nil
  }
}

@Observable @MainActor class SheetConfig {
  let id: AnyHashable?
  let content: AnyView

  init<Content: View>(id: AnyHashable?, @ViewBuilder content: @escaping () -> Content) {
    self.id = id
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
