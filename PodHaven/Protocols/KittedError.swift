// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

protocol KittedError: Throwable, Catching, Equatable {}

extension KittedError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.userFriendlyMessage == rhs.userFriendlyMessage
  }
}
