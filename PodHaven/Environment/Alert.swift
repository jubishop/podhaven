// Copyright Justin Bishop, 2024

import Foundation
import OrderedCollections
import SwiftUI

@Observable @MainActor final class Alert: Sendable {
  static let shared = { Alert() }()

  var config: AlertConfig?

  func callAsFunction(
    _ message: String,
    title: String = "Error",
    actions: OrderedDictionary<String, () -> Void> = ["Ok": {}]
  ) {
    print("Alerting with title: \(title), message: \(message)")
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
}
