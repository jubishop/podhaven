// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation
import OSLog

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

  private let logger: Logger

  // MARK: - Initialization

  init() {
    self.logger = Logger()
  }

  init(subsystem: String, category: String) {
    self.logger = Logger(subsystem: subsystem, category: category)
  }

  // MARK: - Logging Functions

  func trace(_ message: String) {
    if shouldLog(.trace) {
      logger.trace("\(message)")
    }
  }

  func debug(_ message: String) {
    if shouldLog(.debug) {
      logger.debug("\(message)")
    }
  }

  func info(_ message: String) {
    if shouldLog(.info) {
      logger.info("\(message)")
    }
  }

  func warning(_ message: String) {
    if shouldLog(.warning) {
      logger.warning("\(message)")
    }
  }

  func error(
    _ error: any KittedError,
    file: String = #file,
    function: String = #function,
    line: Int = #line
  ) -> any KittedError {
    guard shouldLog(.error)
    else { return error }

    let fileName = "\(file)".components(separatedBy: "/").last ?? "\(file)"
    let stackTrace = StackTracer.capture(limit: 10, drop: 1).joined(separator: "\n")
    let errorChain = ErrorKit.errorChainDescription(for: error)

    logger.error(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Error thrown from: [\(fileName):\(line) \(function)]:
        \(errorChain)

      🧱 Call stack:
        \(stackTrace)
      ----------------------------------------------------------------------------------------------
      """
    )

    return error
  }

  func fatal(_ message: String) {
    fatalError(message)
  }

  // MARK: - Private Helpers

  private func shouldLog(_ level: LogLevel) -> Bool {
    level >= Self.currentLevel
  }
}
