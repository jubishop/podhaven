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

struct Log {
  enum SubsystemAndCategory {
    case database(Database)
    case search(Search)
    case podcasts(Podcasts)

    enum Database: String {
      case appDB
    }

    enum Search: String {
      case main
    }

    enum Podcasts: String {
      case detail
    }

    var subsystem: String {
      switch self {
      case .database: return "database"
      case .search: return "search"
      case .podcasts: return "podcasts"
      }
    }

    var category: String {
      switch self {
      case .database(let category): return category.rawValue
      case .search(let category): return category.rawValue
      case .podcasts(let category): return category.rawValue
      }
    }

    var level: LogLevel {
      switch self {
      case .database(let category):
        switch category {
        case .appDB: return .info
        }
      case .search(let category):
        switch category {
        case .main: return .debug
        }
      case .podcasts(let category):
        switch category {
        case .detail: return .debug
        }
      }
    }
  }

  // MARK: - Static Helpers

  static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }

  // MARK: - Initialization

  private let logger: Logger
  private let level: LogLevel

  init(_ id: SubsystemAndCategory) {
    self.logger = Logger(subsystem: id.subsystem, category: id.category)
    self.level = id.level
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
