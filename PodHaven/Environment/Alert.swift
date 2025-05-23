// Copyright Justin Bishop, 2025

import FactoryKit
import OSLog
import SwiftUI

extension Container {
  @MainActor
  var alert: Factory<Alert> {
    Factory(self) { @MainActor in Alert() }.scope(.cached)
  }
}

@Observable @MainActor final class Alert {
  var config: AlertConfig?

  fileprivate init() {}

  // MARK: - Public Alert Presentation

  func callAsFunction<Actions: View, Message: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    @ViewBuilder message: @escaping () -> Message
  ) {
    config = AlertConfig(title: title, actions: actions, message: message)
  }

  func callAsFunction<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ message: String
  ) {
    self(title: title, actions: actions, message: { Text(message) })
  }

  // MARK: - Private Helpers
}

@Observable @MainActor final class AlertConfig {
  let title: String
  let actions: AnyView
  let message: AnyView

  init<Actions: View, Message: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    @ViewBuilder message: @escaping () -> Message
  ) {
    self.title = title
    self.actions = AnyView(actions())
    self.message = AnyView(message())
  }
}

extension View {
  func customAlert(_ config: Binding<AlertConfig?>) -> some View {
    alert(
      config.wrappedValue?.title ?? "Error",
      isPresented: Binding(
        get: { config.wrappedValue != nil },
        set: { if !$0 { config.wrappedValue = nil } }
      ),
      actions: { config.wrappedValue?.actions },
      message: { config.wrappedValue?.message }
    )
  }
}
