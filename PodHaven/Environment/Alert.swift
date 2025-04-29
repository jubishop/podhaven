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

  func andReport<Actions: View>(
    title: String = "Error",
    @ViewBuilder actions: @escaping () -> Actions = { Button("Ok") {} },
    _ message: String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.report(message, file: file, function: function, line: line)
    self(title: title, actions: actions, message: { Text(message) })
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
    _ error: any Error,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.report(error, file: file, function: function, line: line)
    self(title: title, actions: actions, message: { Text(Self.message(error)) })
  }

  // MARK: - Public Reporting API

  static func report(
    _ message: String,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if DEBUG
    logReport(message, file: file, function: function, line: line)
    #else
    SentrySDK.capture(message: message)
    #endif
  }

  static func report(
    _ error: any Error,
    file: StaticString = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if DEBUG
    logReport(message(error), file: file, function: function, line: line)
    #else
    SentrySDK.capture(error: error)
    #endif
  }

  // MARK: - Private Helpers

  private static func logReport(
    _ message: String,
    file: StaticString,
    function: StaticString,
    line: UInt
  ) {
    let fileName = "\(file)".components(separatedBy: "/").last ?? "\(file)"
    let stackTrace = StackTracer.capture(limit: 10, drop: 2).joined(separator: "\n")

    print(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Reporting error from: [\(fileName):\(line) \(function)]
      \(message)

      🧱 Call stack:
      \(stackTrace)
      ----------------------------------------------------------------------------------------------

      """
    )
  }

  private static func message(_ error: any Error) -> String {
    guard let err = error as? Err
    else { return error.localizedDescription }

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
