// Copyright Justin Bishop, 2025

import Factory
import SwiftUI

#if !DEBUG
  import Sentry
#endif

extension Container {
  var alert: Factory<Alert> {
    Factory(self) { @MainActor in Alert() }.scope(.singleton)
  }
}

@Observable @MainActor final class Alert {
  var config: AlertConfig?

  fileprivate init() {}

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
    self(title: title, actions: actions, message: { Text(Self.message(error)) })
  }

  func andReport<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ error: any Error
  ) {
    Self.report(error)
    self(title: title, actions: actions, message: { Text(Self.message(error)) })
  }

  static func report(_ error: any Error) {
    print("Error: \(message(error))")
    #if !DEBUG
      SentrySDK.capture(error: error)
    #endif
  }

  // MARK: - Private Helpers

  private static func message(_ error: any Error) -> String {
    guard let err = error as? Err else { return error.localizedDescription }
    return err.localizedDescription
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
