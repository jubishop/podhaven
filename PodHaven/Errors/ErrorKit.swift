// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum ErrorKit {
  // MARK: - Messaging

  static func message(for error: any Error) -> String {
    if let localizedError = error as? any LocalizedError,
      let errorDescription = localizedError.errorDescription
    {
      return errorDescription
    }

    return "[\(domain(for: error)): \(code(for: error))] \(error.localizedDescription)"
  }

  static func loggableMessage(for error: any Error) -> Logger.Message {
    var result = """
      [\(typeName(for: error))]
      \(message(for: error))
      """

    if let underlying = underlyingError(for: error) {
      result += "\n\(underlyingMessage(for: underlying))"
    }

    return Logger.Message(stringLiteral: result)
  }

  // MARK: - Analysis

  static func level(_ error: any Error) -> Logger.Level {
    isRemarkable(error) ? .error : .debug
  }

  static func isRemarkable(_ error: any Error) -> Bool {
    if error is CancellationError { return false }

    if let urlError = error as? URLError,
      urlError.code == .cancelled || urlError.code == .timedOut
    {
      return false
    }

    return true
  }

  // MARK: - Private Formatting Helpers

  private static func underlyingError(for error: any Error) -> (any Error)? {
    (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error
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

  private static func underlyingMessage(for error: any Error) -> String {
    var result = "Underlying: \(typeName(for: error)) ->\n  \(nested(message(for: error)))"

    if let underlying = underlyingError(for: error) {
      result += "\n  \(nested(underlyingMessage(for: underlying)))"
    }

    return result
  }
}
