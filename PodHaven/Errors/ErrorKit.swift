// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum ErrorKit {
  // MARK: - Messaging

  static func coreMessage(for error: any Error) -> String {
    let topLevelMessage = simpleMessage(for: error)
    if !topLevelMessage.isEmpty { return topLevelMessage }
    return simpleMessage(for: baseError(for: error))
  }

  static func message(for error: any Error) -> String {
    let message = simpleMessage(for: error)

    guard let readableError = error as? any ReadableError,
      let caughtError = readableError.caughtError
    else { return message }

    if message.isEmpty {
      return nestedCaughtMessage(for: caughtError)
    }

    return """
      \(message)
      \(nestedCaughtMessage(for: caughtError))
      """
  }

  static func loggableMessage(for error: any Error) -> Logger.Message {
    Logger.Message(
      stringLiteral: """
        [\(typeName(for: error))]
        \(message(for: error))
        """
    )
  }

  // MARK: - Analysis

  static func baseError(for error: any Error) -> any Error {
    guard let readableError = error as? any ReadableError,
      let caughtError = readableError.caughtError
    else { return error }

    return baseError(for: caughtError)
  }

  static func isRemarkable(_ error: any Error) -> Bool {
    let baseError = baseError(for: error)
    if baseError is CancellationError { return false }

    if let urlError = baseError as? URLError,
      urlError.code == .cancelled || urlError.code == .timedOut
    {
      return false
    }

    return true
  }

  // MARK: - Private Formatting Helpers

  private static func simpleMessage(for error: any Error) -> String {
    if let readableError = error as? any ReadableError {
      return readableError.message
    }

    if let localizedError = error as? any LocalizedError,
      let errorDescription = localizedError.errorDescription
    {
      return errorDescription
    }

    return "[\(domain(for: error)): \(code(for: error))] \(error.localizedDescription)"
  }

  private static func typeName(for error: any Error) -> String {
    let mirror = Mirror(reflecting: error)
    let type = String(describing: type(of: error))

    // For enums, ezpz
    if mirror.displayStyle == .enum, let label = mirror.children.first?.label {
      return "\(type).\(label)"
    }

    // Shorten the caseName to just prefix before any [ or (
    var caseName = String(describing: error)
    if let range = caseName.range(of: "[ (]", options: .regularExpression) {
      caseName = String(caseName[..<range.lowerBound])
    }

    return "\(type).\(caseName)"
  }

  static func domain(for error: any Error) -> String {
    let nsError = error as NSError
    return nsError.domain
  }

  static func code(for error: any Error) -> Int {
    let nsError = error as NSError
    return nsError.code
  }

  // MARK: - Private Messaging Helpers

  private static func nested(_ message: String) -> String {
    message
      .components(separatedBy: .newlines)
      .joined(separator: "\n  ")
  }

  private static func nestedMessage(for error: any Error) -> String {
    nested(message(for: error))
  }

  private static func nestedCaughtMessage(for error: any Error) -> String {
    "\(typeName(for: error)) ->\n  \(nestedMessage(for: error))"
  }
}
