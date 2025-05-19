// Copyright Justin Bishop, 2025

import Foundation

protocol ReadableError: CustomNSError, Equatable, LocalizedError, Sendable {
  var message: String { get }
  var caughtError: Error? { get }
  var baseError: Error { get }
}

extension ReadableError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.message == rhs.message
  }

  var errorUserInfo: [String: Any] {
    [NSDebugDescriptionErrorKey: ErrorKit.loggableMessage(for: self)]
  }

  var errorDescription: String? { message }

  var caughtError: Error? { nil }

  var baseError: Error {
    guard let next = caughtError else { return self }

    return (next as? any ReadableError)?.baseError ?? next
  }
}

extension ReadableError where Self: RawRepresentable, RawValue == String {
  var message: String { rawValue }
}
