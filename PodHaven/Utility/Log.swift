// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation
import OSLog

#if !DEBUG
import Sentry
#endif

private enum LogLevel: Int, Comparable {
  static func currentLevel() -> Self {
    #if DEBUG
    return .debug
    #else
    return .none
    #endif
  }

  case trace = 0
  case debug = 1
  case info = 2
  case warning = 3
  case error = 4
  case none = 99

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct Log {
  private static let currentLevel: LogLevel = LogLevel.currentLevel()
  private static let shared: Log = Log()

  private let logger: Logger

  // MARK: - Initialization

  init() {
    self.logger = Logger()
  }

  init(subsystem: String, category: String) {
    self.logger = Logger(subsystem: subsystem, category: category)
  }

  // MARK: - Special Logging

  static func fatal(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) -> Never {
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n  ")

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Fatal from: [\(fileName(from: file)):\(line) \(function)]
        \(message)

      🧱 Call stack:
        \(stackTrace)
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  static func report(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    shared.report(message, file: file, function: function, line: line)
  }

  func report(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if DEBUG
    self.error(message, file: file, function: function, line: line)
    #else
    SentrySDK.capture(message: message)
    #endif
  }

  static func report(
    _ error: any KittedError,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    shared.report(error, file: file, function: function, line: line)
  }

  func report(
    _ error: any KittedError,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if DEBUG
    self.error(error, file: file, function: function, line: line)
    #else
    SentrySDK.capture(error: error)
    #endif
  }

  // MARK: - Basic Logging

  static func trace(_ message: String) {
    Self.shared.trace(message)
  }

  func trace(_ message: String) {
    if shouldLog(.trace) {
      logger.trace("\(message)")
    }
  }

  static func debug(_ message: String) {
    Self.shared.debug(message)
  }

  func debug(_ message: String) {
    if shouldLog(.debug) {
      logger.debug("\(message)")
    }
  }

  static func info(_ message: String) {
    Self.shared.info(message)
  }

  func info(_ message: String) {
    if shouldLog(.info) {
      logger.info("\(message)")
    }
  }

  static func warning(_ message: String) {
    Self.shared.warning(message)
  }

  func warning(_ message: String) {
    if shouldLog(.warning) {
      logger.warning("\(message)")
    }
  }

  static func error(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.shared.error(message, file: file, function: function, line: line)
  }

  func error(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    guard shouldLog(.error)
    else { return }

    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n  ")

    logger.error(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Error from: [\(Self.fileName(from: file)):\(line) \(function)]:
        \(message)

      🧱 Call stack:
        \(stackTrace)
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  static func error(
    _ error: any KittedError,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.shared.error(error, file: file, function: function, line: line)
  }

  func error(
    _ error: any KittedError,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    guard shouldLog(.error)
    else { return }

    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n  ")
    let errorChain = ErrorKit.errorChainDescription(for: error)

    logger.error(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Error from: [\(Self.fileName(from: file)):\(line) \(function)]:
        \(errorChain)

      🧱 Call stack:
        \(stackTrace)
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  // MARK: - Private Helpers

  private static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }

  private func shouldLog(_ level: LogLevel) -> Bool {
    level >= Self.currentLevel
  }
}
