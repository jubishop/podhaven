// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("TimeInterval formatting", .container)
struct TimeIntervalTests {
  // MARK: - compactReadableFormat Tests

  @Test("compact format for seconds only")
  func testCompactFormatSecondsOnly() {
    #expect(TimeInterval.seconds(0).compactReadableFormat == "0s")
    #expect(TimeInterval.seconds(5).compactReadableFormat == "5s")
    #expect(TimeInterval.seconds(30).compactReadableFormat == "30s")
    #expect(TimeInterval.seconds(59).compactReadableFormat == "59s")
  }

  @Test("compact format for minutes and seconds")
  func testCompactFormatMinutesAndSeconds() {
    #expect(TimeInterval.seconds(60).compactReadableFormat == "1m 0s")
    #expect(TimeInterval.seconds(90).compactReadableFormat == "1m 30s")
    #expect(TimeInterval.seconds(125).compactReadableFormat == "2m 5s")
    #expect(TimeInterval.minutes(5).compactReadableFormat == "5m 0s")
    #expect(TimeInterval.seconds(3599).compactReadableFormat == "59m 59s")
  }

  @Test("compact format for hours and minutes")
  func testCompactFormatHoursAndMinutes() {
    #expect(TimeInterval.hours(1).compactReadableFormat == "1h 0m")
    #expect(TimeInterval.seconds(3600).compactReadableFormat == "1h 0m")
    #expect(TimeInterval.seconds(3660).compactReadableFormat == "1h 1m")
    #expect(TimeInterval.seconds(5400).compactReadableFormat == "1h 30m")
    #expect(TimeInterval.hours(2).compactReadableFormat == "2h 0m")
    #expect(TimeInterval.seconds(7265).compactReadableFormat == "2h 1m")
  }

  @Test("compact format for negative seconds")
  func testCompactFormatNegativeSeconds() {
    #expect(TimeInterval.seconds(-5).compactReadableFormat == "-5s")
    #expect(TimeInterval.seconds(-30).compactReadableFormat == "-30s")
    #expect(TimeInterval.seconds(-59).compactReadableFormat == "-59s")
  }

  @Test("compact format for negative minutes and seconds")
  func testCompactFormatNegativeMinutesAndSeconds() {
    #expect(TimeInterval.seconds(-60).compactReadableFormat == "-1m 0s")
    #expect(TimeInterval.seconds(-90).compactReadableFormat == "-1m 30s")
    #expect(TimeInterval.seconds(-125).compactReadableFormat == "-2m 5s")
    #expect(TimeInterval.minutes(-5).compactReadableFormat == "-5m 0s")
    #expect(TimeInterval.seconds(-3599).compactReadableFormat == "-59m 59s")
  }

  @Test("compact format for negative hours and minutes")
  func testCompactFormatNegativeHoursAndMinutes() {
    #expect(TimeInterval.hours(-1).compactReadableFormat == "-1h 0m")
    #expect(TimeInterval.seconds(-3600).compactReadableFormat == "-1h 0m")
    #expect(TimeInterval.seconds(-3660).compactReadableFormat == "-1h 1m")
    #expect(TimeInterval.seconds(-5400).compactReadableFormat == "-1h 30m")
    #expect(TimeInterval.hours(-2).compactReadableFormat == "-2h 0m")
    #expect(TimeInterval.seconds(-7265).compactReadableFormat == "-2h 1m")
  }

  // MARK: - playbackTimeFormat Tests

  @Test("playback format for seconds only")
  func testPlaybackFormatSecondsOnly() {
    #expect(TimeInterval.seconds(0).playbackTimeFormat == "0:00")
    #expect(TimeInterval.seconds(5).playbackTimeFormat == "0:05")
    #expect(TimeInterval.seconds(30).playbackTimeFormat == "0:30")
    #expect(TimeInterval.seconds(59).playbackTimeFormat == "0:59")
  }

  @Test("playback format for minutes and seconds")
  func testPlaybackFormatMinutesAndSeconds() {
    #expect(TimeInterval.seconds(60).playbackTimeFormat == "1:00")
    #expect(TimeInterval.seconds(90).playbackTimeFormat == "1:30")
    #expect(TimeInterval.seconds(125).playbackTimeFormat == "2:05")
    #expect(TimeInterval.minutes(5).playbackTimeFormat == "5:00")
    #expect(TimeInterval.seconds(600).playbackTimeFormat == "10:00")
    #expect(TimeInterval.seconds(3599).playbackTimeFormat == "59:59")
  }

  @Test("playback format for hours, minutes and seconds")
  func testPlaybackFormatHoursMinutesAndSeconds() {
    #expect(TimeInterval.hours(1).playbackTimeFormat == "1:00:00")
    #expect(TimeInterval.seconds(3600).playbackTimeFormat == "1:00:00")
    #expect(TimeInterval.seconds(3660).playbackTimeFormat == "1:01:00")
    #expect(TimeInterval.seconds(3665).playbackTimeFormat == "1:01:05")
    #expect(TimeInterval.seconds(5400).playbackTimeFormat == "1:30:00")
    #expect(TimeInterval.hours(2).playbackTimeFormat == "2:00:00")
    #expect(TimeInterval.seconds(7265).playbackTimeFormat == "2:01:05")
    #expect(TimeInterval.seconds(36000).playbackTimeFormat == "10:00:00")
  }

  @Test("playback format pads correctly")
  func testPlaybackFormatPadding() {
    #expect(TimeInterval.seconds(61).playbackTimeFormat == "1:01")
    #expect(TimeInterval.seconds(3601).playbackTimeFormat == "1:00:01")
    #expect(TimeInterval.seconds(3661).playbackTimeFormat == "1:01:01")
  }

  @Test("playback format for negative seconds")
  func testPlaybackFormatNegativeSeconds() {
    #expect(TimeInterval.seconds(-5).playbackTimeFormat == "-0:05")
    #expect(TimeInterval.seconds(-30).playbackTimeFormat == "-0:30")
    #expect(TimeInterval.seconds(-59).playbackTimeFormat == "-0:59")
  }

  @Test("playback format for negative minutes and seconds")
  func testPlaybackFormatNegativeMinutesAndSeconds() {
    #expect(TimeInterval.seconds(-60).playbackTimeFormat == "-1:00")
    #expect(TimeInterval.seconds(-90).playbackTimeFormat == "-1:30")
    #expect(TimeInterval.seconds(-125).playbackTimeFormat == "-2:05")
    #expect(TimeInterval.seconds(-600).playbackTimeFormat == "-10:00")
    #expect(TimeInterval.seconds(-3599).playbackTimeFormat == "-59:59")
  }

  @Test("playback format for negative hours, minutes and seconds")
  func testPlaybackFormatNegativeHoursMinutesAndSeconds() {
    #expect(TimeInterval.seconds(-3600).playbackTimeFormat == "-1:00:00")
    #expect(TimeInterval.seconds(-3665).playbackTimeFormat == "-1:01:05")
    #expect(TimeInterval.seconds(-5400).playbackTimeFormat == "-1:30:00")
    #expect(TimeInterval.seconds(-7265).playbackTimeFormat == "-2:01:05")
    #expect(TimeInterval.seconds(-9096).playbackTimeFormat == "-2:31:36")
    #expect(TimeInterval.seconds(-36000).playbackTimeFormat == "-10:00:00")
  }
}
