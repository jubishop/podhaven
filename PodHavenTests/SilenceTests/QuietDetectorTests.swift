// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("Quiet interval detection")
struct QuietDetectorTests {
  @Test("opposite-phase stereo and brief sounds protect audible material")
  func stereo() throws {
    var detector = QuietDetector()
    try detector.consume(
      samples: [Float](repeating: 0, count: 2000),
      channels: 2,
      sampleRate: 1000,
      time: 0
    )
    try detector.consume(samples: [0.01, -0.01], channels: 2, sampleRate: 1000, time: 1)
    try detector.consume(
      samples: [Float](repeating: 0, count: 1998),
      channels: 2,
      sampleRate: 1000,
      time: 1.001
    )
    let map = try detector.finish(duration: 2)
    #expect(map.intervals.count == 2)
    #expect(abs(map.intervals[0].end - 1) < 0.001)
    #expect(map.intervals[1].start >= 1.009)
  }

  @Test("missing timestamps never become silence")
  func discontinuity() throws {
    var detector = QuietDetector()
    try detector.consume(
      samples: [Float](repeating: 0, count: 1000),
      channels: 1,
      sampleRate: 1000,
      time: 0
    )
    try detector.consume(
      samples: [Float](repeating: 0, count: 1000),
      channels: 1,
      sampleRate: 1000,
      time: 5
    )
    let map = try detector.finish(duration: 6)
    #expect(map.intervals.count == 2)
    #expect(map.intervals[0].end <= 1.001)
    #expect(map.intervals[1].start == 5)
  }

  @Test("invalid samples reject analysis")
  func invalid() {
    for sample: Float in [.nan, .infinity, -.infinity] {
      var detector = QuietDetector()
      #expect(throws: SilenceAnalysisError.self) {
        try detector.consume(samples: [sample], channels: 1, sampleRate: 48000, time: 0)
      }
    }
  }

  @Test("quiet audible audio is protected across sample rates")
  func quietAudio() throws {
    for rate in [8000.0, 44100, 48000] {
      var detector = QuietDetector()
      try detector.consume(
        samples: [Float](repeating: 0.002, count: Int(rate)),
        channels: 1,
        sampleRate: rate,
        time: 0
      )
      #expect(try detector.finish(duration: 1).intervals.isEmpty)
    }
  }
}
