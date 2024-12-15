// Copyright Justin Bishop, 2024

import Foundation
import OrderedCollections
import SwiftUI

@Observable @MainActor final class Alert: Sendable {
  static let shared = Alert()

  var config: AlertConfig?

  private init() {}

  func callAsFunction(
    _ message: String,
    title: String = "Error",
    report: String? = nil,
    error: Error? = nil,
    actions: OrderedDictionary<String, () -> Void> = ["Ok": {}]
  ) {
    var message = message
    if let report = report {
      message += "; with report: \"\(report)\""
    }
    self.report(message, error: error, title: title)

    config = AlertConfig(
      title: title,
      actions: {
        ForEach(Array(actions.keys), id: \.self) { label in
          if let action = actions[label] {
            Button(action: action) { Text(label) }
          }
        }
      },
      message: { Text(message) }
    )
  }

  func report(_ message: String, error: Error? = nil, title: String = "Error") {
    // TODO: Send this to Sentry
    var message = message
    if let error = error {
      message += "; with error: \"\(error)\""
    }
    print("Reporting with title: \"\(title)\", message: \"\(message)\"")
  }
}
