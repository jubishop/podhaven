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
    actions: OrderedDictionary<String, () -> Void> = ["Ok": {}]
  ) {
    if let report = report {
      self.report(message + " and report: \"\(report)\"", title: title)
    } else {
      self.report(message, title: title)
    }
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

  func report(_ message: String, title: String = "Error") {
    // TODO: Send this to Sentry
    print("Reporting with title: \"\(title)\", message: \"\(message)\"")
  }
}
