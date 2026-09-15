// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Quiet audio protection format", .container)
struct SilenceProtectionFormatTests {
  @Test("one detector pass completes each protection level, including empty results")
  func allLevels() throws {
    var detector = QuietDetector()
    for (index, amplitude): (Int, Float) in [Float(0.0005), 0.0015, 0.0025, 0.01].enumerated() {
      try detector.consume(
        samples: [Float](repeating: amplitude, count: 1000),
        channels: 1,
        sampleRate: 1000,
        time: Double(index)
      )
    }
    let map = try detector.finish(duration: 4)
    let json = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(map)) as? [String: Any]
    )
    for (level, end) in [("high", 1.0), ("medium", 2.0), ("low", 3.0)] {
      let intervals = try #require(json[level] as? [[String: Double]])
      #expect(intervals.count == 1)
      #expect(abs(try #require(intervals.first?["end"]) - end) < 0.001)
    }
  }

  @Test("legacy single-threshold results and exhausted failures are invalidated")
  func upgrade() async throws {
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: "legacy.mp3")
    )
    let url = try #require(episode.episode.cachedURL)
    try await (Container.shared.fileManager() as! FakeFileManager)
      .writeData(Data("audio".utf8), to: url.rawValue)
    let store = Container.shared.silenceStore()
    _ = try await store.content(for: url.lastPathComponent)
    let legacy = Data(#"{"duration":30,"intervals":[]}"#.utf8)
    try await Container.shared.appDB().writer
      .write { db in
        try db.execute(
          sql: "UPDATE cachedAudioContent SET detectorVersion = 1, analysis = ?, failureCount = 2",
          arguments: [legacy]
        )
      }
    let content = try #require(try await store.content(for: url.lastPathComponent))
    #expect(try content.map == nil)
    #expect(content.failureCount == 0)
    #expect(content.analysis == nil)
  }

  @Test("missing levels fail decoding while three empty levels are complete")
  func completeness() throws {
    for missing in ["high", "medium", "low"] {
      var json: [String: Any] = ["duration": 30, "high": [], "medium": [], "low": []]
      json.removeValue(forKey: missing)
      let content = CachedAudioContent(
        filename: "map.mp3",
        generation: "map",
        detectorVersion: SilenceMap.detectorVersion,
        analysis: try JSONSerialization.data(withJSONObject: json)
      )
      #expect(throws: DecodingError.self) { try content.map }
    }
    let empty = SilenceMap(duration: 30, high: [], medium: [], low: [])
    #expect(empty.isValid)
    let content = CachedAudioContent(
      filename: "map.mp3",
      generation: "map",
      detectorVersion: SilenceMap.detectorVersion,
      analysis: try JSONEncoder().encode(empty)
    )
    #expect(try content.map == empty)
  }

  @Test("the interval bound covers the combined result")
  func combinedLimit() {
    let intervals = (0..<40_000).map { QuietInterval(start: Double($0), end: Double($0) + 0.5) }
    #expect(
      !SilenceMap(duration: 40_000, high: intervals, medium: intervals, low: intervals).isValid
    )
  }

  @Test("obsolete scans cannot publish or record failures after an upgrade")
  func staleVersion() async throws {
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: "obsolete.mp3")
    )
    let url = try #require(episode.episode.cachedURL)
    try await (Container.shared.fileManager() as! FakeFileManager)
      .writeData(Data("audio".utf8), to: url.rawValue)
    let store = Container.shared.silenceStore()
    var old = try #require(try await store.content(for: url.lastPathComponent))
    old.detectorVersion = 1
    let map = SilenceMap(duration: 30, high: [], medium: [], low: [])
    #expect(try await !store.publish(map, for: old))
    try await store.recordFailure(for: old)
    #expect(try await store.content(for: url.lastPathComponent)?.failureCount == 0)
    #expect(try await store.content(for: url.lastPathComponent)?.map == nil)
  }

  @Test("shorten silence help contains exactly two concise paragraphs")
  func help() {
    #expect(
      SilenceSettingsHelp.text == """
        Shortens clear pauses while keeping natural space around speech. Gentle keeps more space, Balanced shortens more, and Aggressive removes the most. Higher playback speeds shorten pauses a little more automatically. Off keeps the original pauses.

        Requires downloaded audio and completed audio analysis. Playback continues normally while analysis is pending.
        """
    )
  }
}
