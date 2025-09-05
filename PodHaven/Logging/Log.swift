// Copyright Justin Bishop, 2025

import Foundation
import Logging
import Synchronization

enum Log {
  // MARK: - Initialization

  #if DEBUG
  private static let subsystemSuffix = Mutex<String>("")
  static func setSubsystemSuffix(_ suffix: String = #function) {
    subsystemSuffix.withLock { $0 = suffix }
  }
  #endif

  static func `as`(_ categorizable: any LogCategorizable) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: buildSubsystem(categorizable.subsystem),
        category: categorizable.category
      )
    )
    logger.logLevel = categorizable.level
    return logger
  }

  static func `as`(_ category: String, level: Logger.Level = .trace) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: buildSubsystem("PodHaven"),
        category: category
      )
    )
    logger.logLevel = level
    return logger
  }

  private static func buildSubsystem(_ subsystem: String) -> String {
    #if DEBUG
    let subsystemSuffix = subsystemSuffix.withLock { string in string }
    return subsystemSuffix.isEmpty ? subsystem : "\(subsystem)_\(subsystemSuffix)"
    #else
    return subsystem
    #endif
  }
}
