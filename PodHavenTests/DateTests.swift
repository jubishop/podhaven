// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of Date tests", .container)
struct DateTests {
  private func utcDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0
  ) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(
      from: DateComponents(
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
      )
    )!
  }

  @Test("parseFeedDate parses RFC-2822 dates")
  func parseRFC2822Dates() {
    #expect(
      Date.parseFeedDate("Fri, 20 Dec 2024 20:00:00 +0000")
        == utcDate(year: 2024, month: 12, day: 20, hour: 20)
    )
  }

  @Test("parseFeedDate parses ISO-8601 datetimes")
  func parseISO8601Datetimes() {
    #expect(
      Date.parseFeedDate("2026-07-07T12:34:56Z")
        == utcDate(year: 2026, month: 7, day: 7, hour: 12, minute: 34, second: 56)
    )
    #expect(
      Date.parseFeedDate("2026-07-07T12:34:56+02:00")
        == utcDate(year: 2026, month: 7, day: 7, hour: 10, minute: 34, second: 56)
    )
  }

  @Test("parseFeedDate parses ISO-8601 datetimes with fractional seconds")
  func parseISO8601DatetimesWithFractionalSeconds() {
    #expect(
      Date.parseFeedDate("2026-07-07T12:34:56.500Z")
        == utcDate(year: 2026, month: 7, day: 7, hour: 12, minute: 34, second: 56)
        .addingTimeInterval(0.5)
    )
  }

  @Test("parseFeedDate parses date-only values")
  func parseDateOnlyValues() {
    #expect(Date.parseFeedDate("2026-07-07") == utcDate(year: 2026, month: 7, day: 7))
    #expect(Date.parseFeedDate("\n  2026-07-07  ") == utcDate(year: 2026, month: 7, day: 7))
  }

  @Test("parseFeedDate returns nil for unparseable values")
  func parseUnparseableValues() {
    #expect(Date.parseFeedDate("sometime last week") == nil)
    #expect(Date.parseFeedDate("") == nil)
    #expect(Date.parseFeedDate("   ") == nil)
  }
}
