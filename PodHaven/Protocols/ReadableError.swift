// Copyright Justin Bishop, 2025

import Foundation

protocol ReadableError: CustomNSError, Equatable, LocalizedError, Sendable {
  var message: String { get }
}

extension ReadableError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.message == rhs.message
  }

  var errorUserInfo: [String: Any] {
    [NSDebugDescriptionErrorKey: ErrorKit.loggableMessage(for: self)]
  }

  var errorDescription: String? { message }
}

extension ReadableError where Self: RawRepresentable, RawValue == String {
  var message: String { rawValue }
}
