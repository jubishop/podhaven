// Copyright Justin Bishop, 2026

import CoreMedia
import Testing

@testable import PodHaven

@Suite("of CMTime formatting tests")
struct CMTimeTests {
  @Test("formats minutes and hours")
  func formatsFiniteTimes() {
    #expect(CMTime.seconds(65).description == "1:05")
    #expect(CMTime.seconds(3_665).description == "1:01:05")
    #expect(CMTime.seconds(65).shortDescription == "1m 5s")
    #expect(CMTime.seconds(3_665).shortDescription == "1h 1m")
  }

  @Test("non-numeric times format as Unknown")
  func nonNumericTimesAreUnknown() {
    for time in [CMTime.invalid, .indefinite, .positiveInfinity, .negativeInfinity] {
      #expect(time.description == "Unknown")
      #expect(time.shortDescription == "Unknown")
    }
  }

  @Test("times past Int's range format as Unknown")
  func timesPastIntRangeAreUnknown() {
    for time in [CMTime(value: .max, timescale: 1), CMTime.seconds(Double(Int.max))] {
      #expect(time.description == "Unknown")
      #expect(time.shortDescription == "Unknown")
    }
  }
}
