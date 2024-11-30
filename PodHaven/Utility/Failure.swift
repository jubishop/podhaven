// Copyright Justin Bishop, 2024

import Foundation

enum Failure: Sendable {
  static func fatal(_ message: String) {
    #if targetEnvironment(simulator)
      fatalError(message)
    #else
      // TODO:  Do something user friendly here
    #endif
  }
}
