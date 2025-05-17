// Copyright Justin Bishop, 2025

import Foundation
import OSLog

#if !DEBUG
import Sentry
#endif

enum LogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case notice = 2
  case warning = 3
  case critical = 4
  case ignore = 99

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

struct Log {
  enum SubsystemAndCategory {
    case database(Database)

    var subsystem: String {
      switch self {
      case .database: return "database"
      }
    }

    var category: String {
      switch self {
      case .database(let category): return category.rawValue
      }
    }

    var level: LogLevel {
      switch self {
      case .database(let category):
        switch category {
        case .appDB: return .info
        }
      }
    }

    enum Database: String {
      case appDB
    }
  }

  private static let shared: Log = Log()

  private let logger: Logger
  private let level: LogLevel

  // MARK: - Initialization

  init(level: LogLevel = .debug) {
    self.logger = Logger()
    self.level = level
  }

  init(_ id: SubsystemAndCategory) {
    self.logger = Logger(subsystem: id.subsystem, category: id.category)
    self.level = id.level
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

    fatalError(
      """
      ----------------------------------------------------------------------------------------------
      ❗️ Fatal from: [\(fileName(from: file)):\(line) \(function)]
      \(message)

      🧱 Call stack:
        \(StackTracer.capture(limit: 20, drop: 1).joined(separator: "\n  "))
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
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif
    self.critical(message, file: file, function: function, line: line)
  }

  static func report(
    _ error: Error,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    shared.report(error, file: file, function: function, line: line)
  }

  func report(
    _ error: Error,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if !DEBUG
    SentrySDK.capture(error: error)
    #endif
    self.caught(error, file: file, function: function, line: line)
  }

  static func caught(
    _ error: Error,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.shared.caught(error, file: file, function: function, line: line)
  }

  func caught(
    _ error: Error,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    critical(ErrorKit.loggableMessage(for: error), file: file, function: function, line: line)
  }

  // MARK: - Basic Logging

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

  static func notice(_ message: String) {
    Self.shared.notice(message)
  }

  func notice(_ message: String) {
    if shouldLog(.notice) {
      logger.notice("\(message)")
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

  static func critical(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    Self.shared.critical(message, file: file, function: function, line: line)
  }

  func critical(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    guard shouldLog(.critical)
    else { return }

    logger.critical(
      """
      ----------------------------------------------------------------------------------------------
      ⚡️ Critical from: [\(Self.fileName(from: file)):\(line) \(function)]:
      \(message)

      🧱 Call stack:
        \(StackTracer.capture(limit: 20, drop: 1).joined(separator: "\n  "))
      ----------------------------------------------------------------------------------------------
      """
    )
  }

  // MARK: - Private Helpers

  private static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }

  private func shouldLog(_ level: LogLevel) -> Bool {
    level >= self.level
  }
}
