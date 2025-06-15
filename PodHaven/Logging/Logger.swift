// Copyright Justin Bishop, 2025

import Foundation
import Logging

extension Logger {
  // MARK: - Environment Helpers

  func shouldLog(_ level: Logger.Level) -> Bool {
    logLevel <= level && AppInfo.environment != .appStore
  }

  // MARK: - Special Logging

  func error(_ error: any Error) {
    let message = ErrorKit.loggableMessage(for: error)
    if ErrorKit.isRemarkable(error) {
      self.error(message)
    } else {
      self.notice(message)
    }
  }
}

extension Logger.Level {
  var intValue: Int {
    switch self {
    case .trace: return 0
    case .debug: return 1
    case .info: return 2
    case .notice: return 3
    case .warning: return 4
    case .error: return 5
    case .critical: return 6
    }
  }
}
