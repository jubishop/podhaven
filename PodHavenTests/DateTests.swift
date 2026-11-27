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
    #expect(
      Date.parseFeedDate("07 Jul 2026 12:34:56 +0000")
        == utcDate(year: 2026, month: 7, day: 7, hour: 12, minute: 34, second: 56)
    )
  }

  @Test("parseFeedDate parses RFC-2822 dates that omit the optional seconds")
  func parseRFC2822DatesWithoutSeconds() {
    #expect(
      Date.parseFeedDate("Thu, 31 Mar 2022 22:00 EST")
        == utcDate(year: 2022, month: 4, day: 1, hour: 3)
    )
    #expect(
      Date.parseFeedDate("Thu, 3 Jun 2021 19:30 EST")
        == utcDate(year: 2021, month: 6, day: 4, minute: 30)
    )
    #expect(
      Date.parseFeedDate("31 Mar 2022 22:00 +0000")
        == utcDate(year: 2022, month: 3, day: 31, hour: 22)
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

  @Test("parseFeedDate reads dates without a time zone or offset as UTC")
  func parseDatesWithoutTimeZone() {
    let expected = utcDate(year: 2025, month: 9, day: 1, hour: 10, minute: 30, second: 15)
    #expect(Date.parseFeedDate("Mon, 01 Sep 2025 10:30:15") == expected)
    #expect(Date.parseFeedDate("01 Sep 2025 10:30:15") == expected)
    #expect(
      Date.parseFeedDate("Mon, 01 Sep 2025 10:30") == expected.addingTimeInterval(-15)
    )
    #expect(Date.parseFeedDate("01 Sep 2025 10:30") == expected.addingTimeInterval(-15))
    #expect(Date.parseFeedDate("2025-09-01T10:30:15") == expected)
    #expect(Date.parseFeedDate("2025-09-01T10:30:15.500") == expected.addingTimeInterval(0.5))
  }

  @Test("parseFeedDate reads zone abbreviations the system doesn't parse as fixed offsets")
  func parseFixedOffsetZoneAbbreviations() {
    #expect(
      Date.parseFeedDate("Mon, 01 Sep 2025 10:00:00 BST")
        == utcDate(year: 2025, month: 9, day: 1, hour: 9)
    )
    #expect(
      Date.parseFeedDate("Mon, 01 Sep 2025 10:00:00 CEST")
        == utcDate(year: 2025, month: 9, day: 1, hour: 8)
    )
    #expect(
      Date.parseFeedDate("Mon, 01 Dec 2025 10:00 CET")
        == utcDate(year: 2025, month: 12, day: 1, hour: 9)
    )
    #expect(
      Date.parseFeedDate("01 Sep 2025 10:00:00 AEST")
        == utcDate(year: 2025, month: 9, day: 1)
    )
    #expect(
      Date.parseFeedDate("Mon, 01 Dec 2025 10:00:00 AEDT")
        == utcDate(year: 2025, month: 11, day: 30, hour: 23)
    )
  }

  @Test("parseFeedDate reads Sept as Sep")
  func parseSeptAbbreviation() {
    #expect(
      Date.parseFeedDate("Mon, 01 Sept 2025 10:00:00 +0000")
        == utcDate(year: 2025, month: 9, day: 1, hour: 10)
    )
    #expect(
      Date.parseFeedDate("1 Sept 2025 10:00 BST")
        == utcDate(year: 2025, month: 9, day: 1, hour: 9)
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
