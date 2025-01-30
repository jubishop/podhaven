// Copyright Justin Bishop, 2025

import Foundation

extension Date {
  static let rfc2822: DateFormatter = {
    let rfc2822 = DateFormatter()
    rfc2822.locale = Locale(identifier: "en_US_POSIX")
    rfc2822.timeZone = TimeZone(secondsFromGMT: 0)
    rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return rfc2822
  }()

  static let epoch: Date = Date(timeIntervalSince1970: 0)
}
