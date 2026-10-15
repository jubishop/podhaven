// Copyright Justin Bishop, 2025

import Foundation
import Logging
import StoreKit

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
      \(detailedMessage(for: error))
      """

    if let underlying = underlyingError(for: error) {
      result += "\n\(underlyingMessage(for: underlying))"
    }

    return Logger.Message(stringLiteral: result)
  }

  // MARK: - Analysis

  static func isRemarkable(_ error: any Error) -> Bool {
    if error is CancellationError { return false }

    if let urlError = error as? URLError,
      urlError.code == .cancelled || urlError.code == .timedOut
    {
      return false
    }

    if let storeKitError = error as? StoreKitError, case .userCancelled = storeKitError {
      return false
    }

    return true
  }

  static func isMissingFile(_ error: any Error) -> Bool {
    if let cocoaError = error as? CocoaError,
      cocoaError.code == .fileNoSuchFile || cocoaError.code == .fileReadNoSuchFile
    {
      return true
    }

    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain, nsError.code == ENOENT {
      return true
    }

    if let underlying = underlyingError(for: error) {
      return isMissingFile(underlying)
    }

    return false
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

  private static func detailedMessage(for error: any Error) -> String {
    guard let decodingError = error as? DecodingError else { return message(for: error) }

    let summary: String
    let context: DecodingError.Context
    switch decodingError {
    case .keyNotFound(let key, let keyContext):
      summary = "Missing key: \(key.stringValue)"
      context = keyContext
    case .typeMismatch(let type, let typeContext):
      summary = "Type mismatch: expected \(type)"
      context = typeContext
    case .valueNotFound(let type, let valueContext):
      summary = "Value not found: expected \(type)"
      context = valueContext
    case .dataCorrupted(let corruptedContext):
      summary = "Data corrupted"
      context = corruptedContext
    @unknown default:
      return message(for: error)
    }

    let path =
      context.codingPath
      .enumerated()
      .map { index, key in
        if let intValue = key.intValue { return "[\(intValue)]" }
        return index == 0 ? key.stringValue : ".\(key.stringValue)"
      }
      .joined()

    return """
      \(message(for: error))
      \(summary)
      Coding path: \(path.isEmpty ? "(root)" : path)
      Debug description: \(context.debugDescription)
      """
  }

  private static func underlyingMessage(for error: any Error) -> String {
    var result = "Underlying: \(typeName(for: error)) ->\n  \(nested(detailedMessage(for: error)))"

    if let underlying = underlyingError(for: error) {
      result += "\n  \(nested(underlyingMessage(for: underlying)))"
    }

    return result
  }
}
