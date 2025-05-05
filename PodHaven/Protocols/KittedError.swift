// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

protocol KittedError: Throwable, Catching, Equatable {}

extension KittedError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.userFriendlyMessage == rhs.userFriendlyMessage
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

  static func nested(_ message: String) -> String {
    message
      .components(separatedBy: .newlines)
      .joined(separator: "\n  ")
  }

  static func nestedUserFriendlyMessage(for error: Error) -> String {
    nested(ErrorKit.userFriendlyMessage(for: error))
  }

  func nestedUserFriendlyCaughtMessage(_ caught: Error) -> String {
    Self.typeName(for: self) + " ->\n  " + Self.nestedUserFriendlyMessage(for: caught)
  }

  var nestedUserFriendlyMessage: String { Self.nested(userFriendlyMessage) }
}
