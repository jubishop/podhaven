// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

@Suite("of Timestamp parsing and formatting tests")
struct TimestampTests {
  // MARK: - parse

  @Test("parses minute:second timestamps")
  func parseMinuteSecond() {
    #expect(Timestamp.parse("2:15") == 135)
    #expect(Timestamp.parse("0:00") == 0)
    #expect(Timestamp.parse("0:40") == 40)
    #expect(Timestamp.parse("14:30") == 870)
    #expect(Timestamp.parse("59:59") == 3599)
  }

  @Test("parses hour:minute:second timestamps")
  func parseHourMinuteSecond() {
    #expect(Timestamp.parse("1:02:15") == 3735)
    #expect(Timestamp.parse("0:15:30") == 930)
    #expect(Timestamp.parse("10:15:30") == 36930)
    #expect(Timestamp.parse("0:00:00") == 0)
  }

  @Test("returns nil for invalid timestamps")
  func parseInvalid() {
    #expect(Timestamp.parse("") == nil)
    #expect(Timestamp.parse("5") == nil)
    #expect(Timestamp.parse("1:2:3:4") == nil)
    #expect(Timestamp.parse("abc") == nil)
    #expect(Timestamp.parse("a:bc") == nil)
  }

  // MARK: - format

  @Test("strips unnecessary leading zeros")
  func formatStripsLeadingZeros() {
    #expect(Timestamp.format("00:08:23") == "8:23")
    #expect(Timestamp.format("00:00:45") == "0:45")
    #expect(Timestamp.format("01:05:30") == "1:05:30")
  }

  @Test("preserves already-clean timestamps")
  func formatPreservesClean() {
    #expect(Timestamp.format("0:40") == "0:40")
    #expect(Timestamp.format("5:00") == "5:00")
    #expect(Timestamp.format("1:05:30") == "1:05:30")
  }

  @Test("returns input string for unparseable timestamps")
  func formatPassthroughOnInvalid() {
    #expect(Timestamp.format("not a timestamp") == "not a timestamp")
  }

  // MARK: - regex

  @Test("matches valid timestamps in text")
  func regexMatches() {
    let text = "0:00 Intro 2:15 Topic 1:02:15 Deep Dive"
    let matches = text.matches(of: Timestamp.regex).map { String($0.output) }
    #expect(matches == ["0:00", "2:15", "1:02:15"])
  }

  @Test("does not match timestamps followed by more digits")
  func regexRejectsTrailingDigits() {
    let text = "5:300 not valid 10:00 valid"
    let matches = text.matches(of: Timestamp.regex).map { String($0.output) }
    #expect(matches == ["10:00"])
  }

  @Test("skips positions where lookahead fails due to trailing colons")
  func regexSkipsTrailingColons() {
    let text = "1:02:03:04 mixed 5:00 valid"
    let matches = text.matches(of: Timestamp.regex).map { String($0.output) }
    #expect(matches == ["02:03:04", "5:00"])
  }
}
