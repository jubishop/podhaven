// Copyright Justin Bishop, 2025

import Foundation

extension Date {
  static let epoch: Date = Date(timeIntervalSince1970: 0)

  // MARK: - Static Formatting Helpers

  static let rfc2822: DateFormatter = {
    let rfc2822 = DateFormatter()
    rfc2822.locale = Locale(identifier: "en_US_POSIX")
    rfc2822.timeZone = TimeZone(secondsFromGMT: 0)
    rfc2822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return rfc2822
  }()

  private static let dateOnly: DateFormatter = {
    let dateOnly = DateFormatter()
    dateOnly.locale = Locale(identifier: "en_US_POSIX")
    dateOnly.timeZone = TimeZone(secondsFromGMT: 0)
    dateOnly.dateFormat = "yyyy-MM-dd"
    return dateOnly
  }()

  // MARK: - Feed Date Parsing

  static func parseFeedDate(_ string: String) -> Date? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let date = rfc2822.date(from: trimmed) { return date }
    if let date = ISO8601DateFormatter().date(from: trimmed) { return date }
    return dateOnly.date(from: trimmed)
  }

  static let usShortDateFormat: DateFormatter = {
    let usShortDateFormat = DateFormatter()
    usShortDateFormat.locale = Locale(identifier: "en_US_POSIX")
    usShortDateFormat.dateFormat = "M/d/yy"
    return usShortDateFormat
  }()

  static let usShortDateFormatWithTime: DateFormatter = {
    let usShortDateFormatWithTime = DateFormatter()
    usShortDateFormatWithTime.locale = Locale(identifier: "en_US_POSIX")
    usShortDateFormatWithTime.dateFormat = "M/d/yyyy h:mm a"
    return usShortDateFormatWithTime
  }()

  // MARK: - Formatting Helpers

  var usShort: String {
    Date.usShortDateFormat.string(from: self)
  }

  var usShortWithTime: String {
    Date.usShortDateFormatWithTime.string(from: self)
  }

  // MARK: - Equality

  func approximatelyEquals(_ date: Date, accuracy: Duration = .seconds(10)) -> Bool {
    abs(self.timeIntervalSince1970 - date.timeIntervalSince1970)
      < Double(accuracy.components.seconds) + (Double(accuracy.components.attoseconds) / 1e18)
  }
}
