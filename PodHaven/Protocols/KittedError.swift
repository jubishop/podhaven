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

  static func typeName(for error: any Error) -> String {
    String(describing: type(of: error))
  }

  static func typeAndCaseName(for error: any Error) -> String {
    let mirror = Mirror(reflecting: error)
    let typeName = String(describing: type(of: error))

    guard let caseName = mirror.children.first?.label else { return typeName }
    return "\(typeName).\(caseName)"
  }

  func userFriendlyCaughtMessage(caught: Error) -> String {
    let message = Self.typeName(for: self) + "\n└─ "

    guard let kittedError = caught as? (any KittedError)
    else { return message + ErrorKit.userFriendlyMessage(for: caught) }

    return message + kittedError.nestedUserFriendlyMessage
  }

  var nestedUserFriendlyMessage: String {
    nestableUserFriendlyMessage
      .components(separatedBy: .newlines)
      .joined(separator: "\n" + "  ")
  }

  var userFriendlyMessage: String {
    nestedUserFriendlyMessage
  }
}
