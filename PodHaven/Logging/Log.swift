// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum Log {
  static let subsystemKey = "subsystem"
  static let categoryKey = "category"

  // MARK: - Initialization

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(label: "com.artisanalsoftware.PodHaven")
    logger[metadataKey: subsystemKey] = Logger.MetadataValue(stringLiteral: categorizable.subsystem)
    logger[metadataKey: categoryKey] = Logger.MetadataValue(stringLiteral: categorizable.category)
    logger.logLevel = categorizable.level
    return logger
  }
}
