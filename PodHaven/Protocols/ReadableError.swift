// Copyright Justin Bishop, 2025 

import Foundation

protocol ReadableError: Equatable, LocalizedError, Sendable {
  var message: String { get }
}

extension ReadableError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.message == rhs.message
  }

  var errorDescription: String? { message }
}

extension ReadableError where Self: RawRepresentable, RawValue == String {
  var message: String { rawValue }
}
