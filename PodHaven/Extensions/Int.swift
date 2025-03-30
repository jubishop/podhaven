// Copyright Justin Bishop, 2025

import Foundation

extension Int {
  var minutes: TimeInterval {
    TimeInterval(self * 60)
  }

  var minutesAgo: Date {
    Date().addingTimeInterval(-minutes)
  }
}
