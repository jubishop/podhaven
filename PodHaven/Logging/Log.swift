// Copyright Justin Bishop, 2025

import Foundation
import Logging

struct Log {
  // MARK: - Static Helpers

  static func merge(
    handler: Logger.Metadata,
    provider: Logger.MetadataProvider?,
    oneOff: Logger.Metadata?
  ) -> Logger.Metadata {
    var merged = handler
    if let provider = provider {
      for (key, value) in provider.get() {
        merged[key] = value
      }
    }
    if let oneOff = oneOff {
      for (key, value) in oneOff {
        merged[key] = value
      }
    }
    return merged
  }

  static func fileName(from filePath: String) -> String {
    filePath.components(separatedBy: "/").suffix(2).joined(separator: "/")
  }

  // MARK: - Initialization

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(label: "com.artisanalsoftware.PodHaven")
    logger[metadataKey: "subsystem"] = Logger.MetadataValue(stringLiteral: categorizable.subsystem)
    logger[metadataKey: "category"] = Logger.MetadataValue(stringLiteral: categorizable.category)
    logger.logLevel = categorizable.level
    return logger
  }
}
