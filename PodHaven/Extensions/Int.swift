// Copyright Justin Bishop, 2025

import Foundation

extension Int {
  var seconds: Duration {
    .seconds(Double(self))
  }

  var minutes: Duration {
    .seconds(Double(self * 60))
  }

  var hours: Duration {
    .minutes(Double(self * 60))
  }

  var days: Duration {
    .hours(Double(self * 24))
  }

  var minutesAgo: Date {
    Date().addingTimeInterval(-minutes.asTimeInterval)
  }

  var hoursAgo: Date {
    Date().addingTimeInterval(-hours.asTimeInterval)
  }

  var daysAgo: Date {
    Date().addingTimeInterval(-days.asTimeInterval)
  }
}
