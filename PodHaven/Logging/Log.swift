// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum Log {
  // MARK: - Initialization

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(label: "com.artisanalsoftware.PodHaven")
    logger[metadataKey: "subsystem"] = Logger.MetadataValue(stringLiteral: categorizable.subsystem)
    logger[metadataKey: "category"] = Logger.MetadataValue(stringLiteral: categorizable.category)
    logger.logLevel = categorizable.level
    return logger
  }
}
