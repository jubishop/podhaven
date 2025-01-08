// Copyright Justin Bishop, 2025

import Foundation
import OrderedCollections
import Sentry
import SwiftUI

@Observable @MainActor final class Alert: Sendable {
  static let shared = Alert()

  var config: AlertConfig<AnyView, Text>?

  private init() {}

  func callAsFunction(
    _ message: String,
    title: String = "Error",
    report: String? = nil,
    error: Error? = nil,
    @ViewBuilder actions: () -> AnyView = { AnyView(Button("Ok") {}) }
  ) {
    var message = message
    if let report = report {
      message += "; with report: \"\(report)\""
    }
    self.report(message, error: error)

    config = AlertConfig(
      title: title,
      actions: actions,
      message: { Text(message) }
    )
  }

  func report(_ message: String, error: Error? = nil) {
    print("Reporting: \(message)")
    SentrySDK.capture(message: message)
    if let error = error {
      print("Error: \(error.localizedDescription)")
      SentrySDK.capture(error: error)
    }
  }
}
