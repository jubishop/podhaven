// Copyright Justin Bishop, 2025

import SwiftUI

#if !DEBUG
  import Sentry
#endif

@Observable @MainActor final class Alert {
  var config: AlertConfig?

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

  func andReport<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ message: String
  ) {
    Self.report(message)
    self(title: title, actions: actions, message: { Text(message) })
  }

  static func report(_ message: String) {
    print("Reporting: \(message)")
    #if !DEBUG
      SentrySDK.capture(message: message)
    #endif
  }

  func callAsFunction<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ error: any Error
  ) {
    self(title: title, actions: actions, message: { Text(error.localizedDescription) })
  }

  func andReport<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ error: any Error
  ) {
    Self.report(error)
    self(title: title, actions: actions, message: { Text(error.localizedDescription) })
  }

  static func report(_ error: Error) {
    print("Error: \(error.localizedDescription)")
    #if !DEBUG
      SentrySDK.capture(error: error)
    #endif
  }

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
      config.wrappedValue?.title ?? "",
      isPresented: Binding(
        get: { config.wrappedValue != nil },
        set: { if !$0 { config.wrappedValue = nil } }
      ),
      actions: { config.wrappedValue?.actions },
      message: { config.wrappedValue?.message }
    )
  }
}
