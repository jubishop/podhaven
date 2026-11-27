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

  // Formats without a zone or offset read as UTC.
  private static let feedDateFormatters: [DateFormatter] =
    [rfc2822]
    + [
      "dd MMM yyyy HH:mm:ss zzz",
      "EEE, dd MMM yyyy HH:mm zzz",
      "dd MMM yyyy HH:mm zzz",
      "EEE, dd MMM yyyy HH:mm:ss",
      "dd MMM yyyy HH:mm:ss",
      "EEE, dd MMM yyyy HH:mm",
      "dd MMM yyyy HH:mm",
      "yyyy-MM-dd'T'HH:mm:ssXXXXX",
      "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
      "yyyy-MM-dd'T'HH:mm:ss",
      "yyyy-MM-dd'T'HH:mm:ss.SSS",
      "yyyy-MM-dd",
    ]
    .map(feedDateFormatter)

  // The formatters don't parse these zone abbreviations.
  private static let feedDateZoneOffsets = [
    "BST": "+0100",
    "CET": "+0100",
    "CEST": "+0200",
    "AEST": "+1000",
    "AEDT": "+1100",
  ]

  static func parseFeedDate(_ string: String) -> Date? {
    var normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacing(" Sept ", with: " Sep ")
    guard !normalized.isEmpty else { return nil }
    if let zone = normalized.split(separator: " ").last,
      let offset = feedDateZoneOffsets[String(zone)]
    {
      normalized = String(normalized.dropLast(zone.count)) + offset
    }
    for formatter in feedDateFormatters {
      if let date = formatter.date(from: normalized) { return date }
    }
    return nil
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
