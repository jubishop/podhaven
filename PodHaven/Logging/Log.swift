// Copyright Justin Bishop, 2025

import Foundation
import Logging
import Synchronization

enum Log {
  // MARK: - Initialization

  #if DEBUG
  private static let _subsystem = Mutex<String>("")
  static func setSubsystem(_ subsystem: String = #function) {
    _subsystem.withLock { $0 = subsystem }
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
    let _subsystem = _subsystem.withLock { string in string }
    return _subsystem.isEmpty ? subsystem : "\(_subsystem)_\(subsystem)"
    #else
    return subsystem
    #endif
  }
}
