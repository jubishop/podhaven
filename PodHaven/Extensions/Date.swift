// Copyright Justin Bishop, 2025

import Foundation

extension Date {
  static let epoch: Date = Date(timeIntervalSince1970: 0)

  // MARK: - Static Formatting Helpers

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

  // MARK: - Feed Date Parsing

  private static func feedDateFormatter(_ format: String) -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = format
    return formatter
  }

  static let rfc2822: DateFormatter = feedDateFormatter("EEE, dd MMM yyyy HH:mm:ss zzz")

  private static let rfc2822NoWeekday: DateFormatter = feedDateFormatter(
    "dd MMM yyyy HH:mm:ss zzz"
  )

  private static let iso8601: DateFormatter = feedDateFormatter("yyyy-MM-dd'T'HH:mm:ssXXXXX")

  private static let iso8601WithFractionalSeconds: DateFormatter = feedDateFormatter(
    "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
  )

  private static let dateOnly: DateFormatter = feedDateFormatter("yyyy-MM-dd")

  static func parseFeedDate(_ string: String) -> Date? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let date = rfc2822.date(from: trimmed) { return date }
    if let date = rfc2822NoWeekday.date(from: trimmed) { return date }
    if let date = iso8601.date(from: trimmed) { return date }
    if let date = iso8601WithFractionalSeconds.date(from: trimmed) { return date }
    return dateOnly.date(from: trimmed)
  }

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
