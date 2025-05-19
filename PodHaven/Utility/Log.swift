// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import OSLog

#if !DEBUG
import Sentry
#endif

enum LogLevel: Int, Comparable {
  case debug = 0
  case info = 1
  case warning = 2
  case critical = 3

  static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

protocol LogIdentifiable {
  var subsystem: String { get }
  var level: LogLevel { get }
  var category: String { get }
}

extension LogIdentifiable where Self: RawRepresentable, RawValue == String {
  var category: String { self.rawValue }
}

enum LogContext {
  enum Search: String, LogIdentifiable {
    case main

    var subsystem: String { "search" }

    var level: LogLevel {
      switch self {
      case .main: return .debug
      }
    }
  }

  enum Database: String, LogIdentifiable {
    case appDB

    var subsystem: String { "database" }

    var level: LogLevel {
      switch self {
      case .appDB: return .info
      }
    }
  }

  enum Podcasts: String, LogIdentifiable {
    case detail

    var subsystem: String { "podcasts" }

    var level: LogLevel {
      switch self {
      case .detail: return .debug
      }
    }
  }
}

struct Log {
  // MARK: - Static Helpers

  static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }

  // MARK: - Initialization

  private let logger: Logger
  private let level: LogLevel

  init(_ context: LogIdentifiable) {
    self.logger = Logger(subsystem: context.subsystem, category: context.category)
    self.level = context.level
  }

  // MARK: - Sentry Reporting

  func report(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    #if !DEBUG
    SentrySDK.capture(message: message)
    #endif

    critical(message, file: file, function: function, line: line)
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

    critical(error, file: file, function: function, line: line)
  }

  // MARK: - Basic Logging

  func debug(_ error: Error) {
    debug(ErrorKit.loggableMessage(for: error))
  }

  func debug(_ message: String) {
    if shouldLog(.debug) {
      logger.debug("\(message)")
    }
  }

  func info(_ error: Error) {
    info(ErrorKit.loggableMessage(for: error))
  }

  func info(_ message: String) {
    if shouldLog(.info) {
      logger.info("\(message)")
    }
  }

  func warning(_ error: Error) {
    warning(ErrorKit.loggableMessage(for: error))
  }

  func warning(_ message: String) {
    if shouldLog(.warning) {
      logger.warning("\(message)")
    }
  }

  func critical(
    _ error: Error,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
    critical(ErrorKit.loggableMessage(for: error), file: file, function: function, line: line)
  }

  func critical(
    _ message: String,
    file: String = #file,
    function: StaticString = #function,
    line: UInt = #line
  ) {
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

  private func shouldLog(_ level: LogLevel) -> Bool {
    level >= self.level
  }
}
