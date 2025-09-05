// Copyright Justin Bishop, 2025

import Foundation
import Logging
import Synchronization

enum Log {
  // MARK: - Initialization

  #if DEBUG
  private static let _system = ThreadSafe<String>("")
  static func setSystem(_ system: String = #function) {
    _system(system)
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

  static func `as`(_ category: String, level: Logger.Level = .debug) -> Logger {
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
    let system = _system()
    return system.isEmpty ? subsystem : "\(system)_\(subsystem)"
    #else
    return subsystem
    #endif
  }
}
