// Copyright Justin Bishop, 2025

import Foundation

extension Int {
  var minutes: TimeInterval {
    TimeInterval(self * 60)
  }

  var hours: TimeInterval {
    TimeInterval(self * 60 * 60)
  }

  var minutesAgo: Date {
    Date().addingTimeInterval(-minutes)
  }

  var hoursAgo: Date {
    Date().addingTimeInterval(-hours)
  }
}
