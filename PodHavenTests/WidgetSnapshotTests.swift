// Copyright Justin Bishop, 2026

import AppIntents
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetSnapshot tests")
struct WidgetSnapshotTests {

  // MARK: - NowPlayingSnapshot Round-Trip

  @Test("NowPlayingSnapshot encodes and decodes with all fields intact")
  func nowPlayingRoundTrip() throws {
    let artworkBase64 = Data(repeating: 0xFF, count: 100).base64EncodedString()
    let pubDate: Double = 1_700_000_000

    let snapshot = NowPlayingSnapshot(
      schemaVersion: NowPlayingSnapshot.currentSchemaVersion,
      nowPlaying: NowPlayingSnapshot.NowPlaying(
        episodeID: 42,
        episodeTitle: "Test Episode",
        podcastTitle: "Test Podcast",
        pubDateTimestamp: pubDate,
        durationSeconds: 1800,
        artworkBase64: artworkBase64
      ),
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)

    #expect(decoded.schemaVersion == NowPlayingSnapshot.currentSchemaVersion)
    #expect(decoded.nowPlaying?.episodeID == 42)
    #expect(decoded.nowPlaying?.episodeTitle == "Test Episode")
    #expect(decoded.nowPlaying?.podcastTitle == "Test Podcast")
    #expect(decoded.nowPlaying?.pubDateTimestamp == pubDate)
    #expect(decoded.nowPlaying?.durationSeconds == 1800)
    #expect(decoded.nowPlaying?.artworkBase64 == artworkBase64)
  }

  @Test("NowPlayingSnapshot encodes and decodes with nil nowPlaying")
  func nowPlayingNilRoundTrip() throws {
    let snapshot = NowPlayingSnapshot(
      schemaVersion: NowPlayingSnapshot.currentSchemaVersion,
      nowPlaying: nil,
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)

    #expect(decoded.nowPlaying == nil)
  }

  @Test("NowPlayingSnapshot encodes and decodes with nil artworkBase64")
  func nowPlayingNilArtwork() throws {
    let snapshot = NowPlayingSnapshot(
      schemaVersion: NowPlayingSnapshot.currentSchemaVersion,
      nowPlaying: NowPlayingSnapshot.NowPlaying(
        episodeID: 1,
        episodeTitle: "No Art",
        podcastTitle: "Podcast",
        pubDateTimestamp: Date().timeIntervalSince1970,
        durationSeconds: 600,
        artworkBase64: nil
      ),
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)

    #expect(decoded.nowPlaying?.artworkBase64 == nil)
  }

  @Test("NowPlayingSnapshot unknown schema version is detectable")
  func nowPlayingUnknownSchemaVersion() throws {
    let snapshot = NowPlayingSnapshot(
      schemaVersion: 999,
      nowPlaying: nil,
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(NowPlayingSnapshot.self, from: data)

    #expect(decoded.schemaVersion == 999)
    #expect(decoded.schemaVersion > NowPlayingSnapshot.currentSchemaVersion)
  }

  // MARK: - QueueSnapshot Round-Trip

  @Test("QueueSnapshot encodes and decodes with all fields intact")
  func queueRoundTrip() throws {
    let imageURL = "https://example.com/episode1.jpg"

    let artworkBase64 = Data(repeating: 0xFF, count: 50).base64EncodedString()
    let snapshot = QueueSnapshot(
      schemaVersion: QueueSnapshot.currentSchemaVersion,
      queue: [
        QueueSnapshot.QueueItem(
          episodeID: 100,
          episodeTitle: "Queue Episode 1",
          pubDateTimestamp: Date().timeIntervalSince1970,
          durationSeconds: 3600,
          artworkURL: imageURL
        ),
        QueueSnapshot.QueueItem(
          episodeID: 101,
          episodeTitle: "Queue Episode 2",
          pubDateTimestamp: Date().addingTimeInterval(-86400).timeIntervalSince1970,
          durationSeconds: 2400,
          artworkURL: nil
        ),
      ],
      queueTotalCount: 10,
      artwork: [imageURL: artworkBase64],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(QueueSnapshot.self, from: data)

    #expect(decoded.schemaVersion == QueueSnapshot.currentSchemaVersion)
    #expect(decoded.queue.count == 2)
    #expect(decoded.queueTotalCount == 10)
    #expect(decoded.queue[0].episodeID == 100)
    #expect(decoded.queue[0].episodeTitle == "Queue Episode 1")
    #expect(decoded.queue[0].artworkURL == imageURL)
    #expect(decoded.artwork[imageURL] == artworkBase64)
    #expect(decoded.queue[1].episodeID == 101)
    #expect(decoded.queue[1].artworkURL == nil)
  }

  @Test("QueueSnapshot unknown schema version is detectable")
  func queueUnknownSchemaVersion() throws {
    let snapshot = QueueSnapshot(
      schemaVersion: 999,
      queue: [],
      queueTotalCount: 0,
      artwork: [:],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(QueueSnapshot.self, from: data)

    #expect(decoded.schemaVersion == 999)
    #expect(decoded.schemaVersion > QueueSnapshot.currentSchemaVersion)
  }

  // MARK: - PlaybackStatus Codable

  @Test("PlaybackStatus encodes and decodes all cases")
  func playbackStatusCodable() throws {
    let cases: [PlaybackStatus] = [.playing, .paused, .stopped, .waiting, .loading("Test Episode")]

    for status in cases {
      let data = try JSONEncoder().encode(status)
      let decoded = try JSONDecoder().decode(PlaybackStatus.self, from: data)
      #expect(decoded == status)
    }
  }

  // MARK: - Intent Conformance

  @Test("PlayPauseIntent conforms to AudioPlaybackIntent and SetValueIntent")
  func playPauseIntentConformance() {
    let intent: any AudioPlaybackIntent = PlayPauseIntent()
    #expect(intent is PlayPauseIntent)
    #expect(intent is any SetValueIntent)
  }

  @Test("SkipForwardIntent conforms to AudioPlaybackIntent")
  func skipForwardIntentConformance() {
    let intent: any AudioPlaybackIntent = SkipForwardIntent()
    #expect(intent is SkipForwardIntent)
  }

  @Test("SkipBackwardIntent conforms to AudioPlaybackIntent")
  func skipBackwardIntentConformance() {
    let intent: any AudioPlaybackIntent = SkipBackwardIntent()
    #expect(intent is SkipBackwardIntent)
  }

  // MARK: - Deep Link Parsing

  @Test("now-playing widget URL parses correctly")
  func nowPlayingDeepLink() throws {
    let url = try #require(URL(string: "podhaven://widget/now-playing"))

    #expect(url.host == "widget")
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    #expect(pathComponents.first == "now-playing")
  }

  @Test("queue widget URL with episode ID parses correctly")
  func queueDeepLink() throws {
    let url = try #require(URL(string: "podhaven://widget/queue/12345"))

    #expect(url.host == "widget")
    let pathComponents = url.pathComponents.filter { $0 != "/" }
    #expect(pathComponents.first == "queue")
    #expect(pathComponents.dropFirst().first == "12345")

    let episodeID = try #require(Int64(pathComponents.dropFirst().first ?? ""))
    #expect(episodeID == 12345)
  }

}
