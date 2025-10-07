// Copyright Justin Bishop, 2025

import Foundation
import Logging

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
