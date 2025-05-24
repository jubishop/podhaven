// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum Log {
  // MARK: - Initialization

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        category: categorizable.category,
        subsystem: categorizable.subsystem
      )
    )
    logger.logLevel = categorizable.level
    return logger
  }
}
