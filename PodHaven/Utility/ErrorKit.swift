// Copyright Justin Bishop, 2025

import Foundation

enum ErrorKit {
  static func typeName(for error: Error) -> String {
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

  static func message(for error: Error) -> String {
    if let readableError = error as? any ReadableError {
      return readableError.message
    }

    if let localizedError = error as? LocalizedError,
      let errorDescription = localizedError.errorDescription
    {
      return errorDescription
    }

    return "[\(domain(for: error)): \(code(for: error))] \(error.localizedDescription)"
  }

  static func domain(for error: Error) -> String {
    let nsError = error as NSError
    return nsError.domain
  }

  static func code(for error: Error) -> Int {
    let nsError = error as NSError
    return nsError.code
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
