// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Logging

#if DEBUG
extension Container {
  fileprivate var testLogSystem: Factory<ThreadSafe<String>> {
    Factory(self) { ThreadSafe("") }.scope(.cached)
  }
}
#endif

enum Log {
  // MARK: - Initialization

  #if DEBUG
  static func setTestSystem(_ system: String = #function) {
    Container.shared.testLogSystem()(system)
  }
  static func getTestSystem() -> String {
    Container.shared.testLogSystem()()
  }
  #endif

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

  static func `as`(_ category: String, level: Logger.Level = .debug) -> Logger {
    var logger = Logger(
      label: LogKit.buildLabel(
        subsystem: "PodHaven",
        category: category
      )
    )
    logger.logLevel = level
    return logger
  }
}
