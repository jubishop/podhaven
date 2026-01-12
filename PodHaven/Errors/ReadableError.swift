// Copyright Justin Bishop, 2025

import Foundation

protocol ReadableError: CustomNSError, Equatable, LocalizedError, Sendable {
  var message: String { get }
  var caughtError: (any Error)? { get }
}

extension ReadableError {
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.message == rhs.message
  }

  var errorUserInfo: [String: Any] {
    [NSDebugDescriptionErrorKey: ErrorKit.loggableMessage(for: self)]
  }

  var errorDescription: String? { message }

  static var errorDomain: String { "PodHaven" }
  var errorCode: Int { 1 }
  var failureReason: String? { nil }
  var recoverySuggestion: String? { nil }
  var helpAnchor: String? { nil }
}

extension ReadableError where Self: RawRepresentable, RawValue == String {
  var message: String { rawValue }
}
