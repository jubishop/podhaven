// Copyright Justin Bishop, 2025

import Foundation

struct WrappedError: KittedError {
  static func caught(_ error: Error) -> WrappedError {
    WrappedError(error)
  }

  private let error: Error

  init(_ error: Error) {
    self.error = error
  }

  var userFriendlyMessage: String { Self.userFriendlyMessage(for: error) }
}
