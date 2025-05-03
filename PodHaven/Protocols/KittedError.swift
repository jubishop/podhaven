// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

protocol KittedError: Throwable, Catching, Equatable {}

extension KittedError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    ErrorKit.errorChainDescription(for: lhs) == ErrorKit.errorChainDescription(for: rhs)
  }
}
