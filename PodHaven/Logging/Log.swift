// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum Log {
  // MARK: - Initialization

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: categorizable.subsystem,
        category: categorizable.category
      )
    )
    logger.logLevel = categorizable.level
    return logger
  }

  static func `as`(_ category: String, level: Logger.Level = .trace) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: "PodHaven",
        category: category
      )
    )
    logger.logLevel = level
    return logger
  }

  static func error(_ error: Error, from log: Logger) {
    let message = ErrorKit.loggableMessage(for: error)
    if ErrorKit.isRemarkable(error) {
      log.error(message)
    } else {
      log.notice(message)
    }
  }
}
