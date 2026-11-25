// Copyright Justin Bishop, 2026

import CoreMedia
import Testing

@testable import PodHaven

@Suite("of CMTime formatting tests", .container)
struct CMTimeTests {
  @Test("descriptions format whole hours, minutes, and seconds")
  func descriptionsFormatTime() {
    #expect(CMTime.seconds(45).description == "0:45")
    #expect(CMTime.seconds(45).shortDescription == "0m 45s")
    #expect(CMTime.seconds(3723.25).description == "1:02:03")
    #expect(CMTime.seconds(3723.25).shortDescription == "1h 2m")
  }

  @Test("descriptions are Unknown when the seconds don't fit in Int")
  func descriptionsOfUnrepresentableTimes() {
    for time in [CMTime.invalid, .positiveInfinity, CMTime(value: .max, timescale: 1)] {
      #expect(time.description == "Unknown")
      #expect(time.shortDescription == "Unknown")
    }
  }
}
