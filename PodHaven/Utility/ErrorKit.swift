// Copyright Justin Bishop, 2025

import Foundation

enum ErrorKit {
  static func typeName(for error: Error) -> String {
    let type = String(describing: type(of: error))  // Strips module name
    let fullCase = String(describing: error)

    let caseName: String
    if let parenIndex = fullCase.firstIndex(of: "(") {
      caseName = String(fullCase[..<parenIndex])
    } else {
      caseName = fullCase
    }

    return "\(type).\(caseName)"
  }

  static func message(for error: Error) -> String {
    if let readableError = error as? any ReadableError {
      return readableError.message
    }

    if let localizedError = error as? LocalizedError,
      let errorDescription = localizedError.errorDescription
    {
      return errorDescription
    }

    return error.localizedDescription
  }

  static func loggableMessage(for error: Error) -> String {
    """
    [\(typeName(for: error))]
    \(message(for: error))
    """
  }

  static func nested(_ message: String) -> String {
    message
      .components(separatedBy: .newlines)
      .joined(separator: "\n  ")
  }

  static func nestedMessage(for error: Error) -> String {
    nested(message(for: error))
  }

  static func nestedCaughtMessage(for error: Error) -> String {
    "\(typeName(for: error)) ->\n  \(nestedMessage(for: error))"
  }
}
