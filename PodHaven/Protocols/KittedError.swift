// Copyright Justin Bishop, 2025

import Foundation

protocol KittedError: Equatable, LocalizedError, Sendable {
  static func caught(_ error: Error) -> Self

  var userFriendlyMessage: String { get }
}

extension KittedError {
  static func == (_ lhs: Self, _ rhs: Self) -> Bool {
    lhs.errorDescription == rhs.errorDescription
  }

  static func `catch`<ReturnType>(_ operation: () throws -> ReturnType) throws(Self)
    -> ReturnType
  {
    do {
      return try operation()
    } catch let error as Self {
      throw error
    } catch {
      throw caught(error)
    }
  }

  static func `catch`<ReturnType>(_ operation: @Sendable () async throws -> ReturnType)
    async throws(Self) -> ReturnType
  {
    do {
      return try await operation()
    } catch let error as Self {
      throw error
    } catch {
      throw caught(error)
    }
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

  static func userFriendlyMessage(for error: Error) -> String {
    if let kittedError = error as? any KittedError {
      return kittedError.userFriendlyMessage
    }

    if let localizedError = error as? LocalizedError,
      let errorDescription = localizedError.errorDescription
    {
      return errorDescription
    }

    return error.localizedDescription
  }

  static func nested(_ message: String) -> String {
    message
      .components(separatedBy: .newlines)
      .joined(separator: "\n  ")
  }

  static func nestedUserFriendlyCaughtMessage(for error: Error) -> String {
    "Caught ->\n  " + nestedUserFriendlyMessage(for: error)
  }

  static func nestedUserFriendlyMessage(for error: Error) -> String {
    nested(userFriendlyMessage(for: error))
  }

  var errorDescription: String? { userFriendlyMessage }

  func nestedUserFriendlyCaughtMessage(_ error: Error) -> String {
    Self.typeName(for: self) + " ->\n  " + Self.nestedUserFriendlyMessage(for: error)
  }

  var nestedUserFriendlyMessage: String { Self.nested(userFriendlyMessage) }
}

extension KittedError where Self: RawRepresentable, RawValue == String {
  var userFriendlyMessage: String { rawValue }
}
