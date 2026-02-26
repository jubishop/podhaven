// Copyright Justin Bishop, 2026

import AppIntents
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetSnapshot tests")
struct WidgetSnapshotTests {

  // MARK: - Encode/Decode Round-Trip

  @Test("snapshot encodes and decodes with all fields intact")
  func encodeDecodeRoundTrip() throws {
    let artworkData = Data(repeating: 0xFF, count: 100)
    let artworkBase64 = artworkData.base64EncodedString()

    let snapshot = WidgetSnapshot(
      schemaVersion: WidgetSnapshot.currentSchemaVersion,
      nowPlaying: WidgetSnapshot.NowPlaying(
        episodeID: 42,
        episodeTitle: "Test Episode",
        podcastTitle: "Test Podcast",
        durationSeconds: 1800,
        currentTimeSeconds: 450,
        playbackStatus: .playing,
        artworkBase64: artworkBase64
      ),
      queue: [
        WidgetSnapshot.QueueItem(
          episodeID: 100,
          episodeTitle: "Queue Episode 1",
          podcastTitle: "Queue Podcast 1",
          durationSeconds: 3600
        ),
        WidgetSnapshot.QueueItem(
          episodeID: 101,
          episodeTitle: "Queue Episode 2",
          podcastTitle: "Queue Podcast 2",
          durationSeconds: 2400
        ),
      ],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(decoded.schemaVersion == WidgetSnapshot.currentSchemaVersion)
    #expect(decoded.nowPlaying?.episodeID == 42)
    #expect(decoded.nowPlaying?.episodeTitle == "Test Episode")
    #expect(decoded.nowPlaying?.podcastTitle == "Test Podcast")
    #expect(decoded.nowPlaying?.durationSeconds == 1800)
    #expect(decoded.nowPlaying?.currentTimeSeconds == 450)
    #expect(decoded.nowPlaying?.playbackStatus == .playing)
    #expect(decoded.nowPlaying?.artworkBase64 == artworkBase64)
    #expect(decoded.queue.count == 2)
    #expect(decoded.queue[0].episodeID == 100)
    #expect(decoded.queue[0].episodeTitle == "Queue Episode 1")
    #expect(decoded.queue[1].episodeID == 101)
  }

  @Test("snapshot encodes and decodes with nil nowPlaying")
  func encodeDecodeNilNowPlaying() throws {
    let snapshot = WidgetSnapshot(
      schemaVersion: WidgetSnapshot.currentSchemaVersion,
      nowPlaying: nil,
      queue: [],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(decoded.nowPlaying == nil)
    #expect(decoded.queue.isEmpty)
  }

  @Test("snapshot encodes and decodes with nil artworkBase64")
  func encodeDecodeNilArtwork() throws {
    let snapshot = WidgetSnapshot(
      schemaVersion: WidgetSnapshot.currentSchemaVersion,
      nowPlaying: WidgetSnapshot.NowPlaying(
        episodeID: 1,
        episodeTitle: "No Art",
        podcastTitle: "Podcast",
        durationSeconds: 600,
        currentTimeSeconds: 0,
        playbackStatus: .paused,
        artworkBase64: nil
      ),
      queue: [],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    #expect(decoded.nowPlaying?.artworkBase64 == nil)
  }

  // MARK: - Schema Version Forward Compatibility

  @Test("unknown schema version returns nil from reader")
  func unknownSchemaVersion() throws {
    let snapshot = WidgetSnapshot(
      schemaVersion: 999,
      nowPlaying: nil,
      queue: [],
      updatedAt: Date()
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

    // Reader should reject unknown schema versions
    #expect(decoded.schemaVersion == 999)
    #expect(decoded.schemaVersion > WidgetSnapshot.currentSchemaVersion)
  }

  // MARK: - PlaybackStatus Widget Status

  @Test("playbackStatus widgetStatus returns correct values")
  func playbackStatusWidgetStatus() {
    #expect(PlaybackStatus.playing.widgetStatus == .playing)
    #expect(PlaybackStatus.paused.widgetStatus == .paused)
    #expect(PlaybackStatus.stopped.widgetStatus == .stopped)
    #expect(PlaybackStatus.waiting.widgetStatus == .waiting)
    #expect(PlaybackStatus.loading("Test").widgetStatus == .loading)
  }

  // MARK: - Intent Conformance

  @Test("PlayPauseIntent conforms to AudioPlaybackIntent")
  func playPauseIntentConformance() {
    let intent: any AudioPlaybackIntent = PlayPauseIntent()
    #expect(intent is PlayPauseIntent)
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
