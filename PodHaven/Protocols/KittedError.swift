// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

protocol KittedError: Throwable, Catching, Equatable {
  var nestableUserFriendlyMessage: String { get }
}

extension KittedError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.userFriendlyMessage == rhs.userFriendlyMessage
  }

  static func nested(_ message: String) -> String {
    message
      .components(separatedBy: .newlines)
      .joined(separator: "\n  ")
  }

  static func userFriendlyMessage(for error: Error) -> String {
    nested(ErrorKit.userFriendlyMessage(for: error))
  }

  static func typeName(for error: Error) -> String {
    String(describing: type(of: error))
  }

  static func typeAndCaseName(for error: Error) -> String {
    let mirror = Mirror(reflecting: error)
    let typeName = String(describing: type(of: error))

    guard let caseName = mirror.children.first?.label else { return typeName }
    return "\(typeName).\(caseName)"
  }

  func userFriendlyCaughtMessage(_ caught: Error) -> String {
    Self.typeName(for: self) + " ->\n  " + Self.userFriendlyMessage(for: caught)
  }

  func nestedUserFriendlyMessage() -> String {
    Self.nested(nestableUserFriendlyMessage)
  }

  var userFriendlyMessage: String { nestableUserFriendlyMessage }
}
