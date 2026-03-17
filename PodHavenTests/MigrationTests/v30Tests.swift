// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("v30 migration tests")
struct V30MigrationTests {

  private func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  @Test("migrates now-playing and queue data from legacy snapshot")
  func migratesNowPlayingAndQueue() throws {
    let dir = try makeTempDir()

    let legacy: [String: Any] = [
      "schemaVersion": 4,
      "nowPlaying": [
        "episodeID": 42,
        "episodeTitle": "Test Episode",
        "podcastTitle": "Test Podcast",
        "pubDateTimestamp": 1_700_000_000.0,
        "durationSeconds": 1800.0,
        "artworkBase64": "AAAA",
      ] as [String: Any],
      "queue": [
        [
          "episodeID": 100,
          "episodeTitle": "Queue Ep 1",
          "pubDateTimestamp": 1_700_000_000.0,
          "durationSeconds": 3600.0,
          "artworkBase64": "BBBB",
        ] as [String: Any]
      ],
      "queueTotalCount": 5,
      "updatedAt": 1_700_000_000.0,
    ]
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    try legacyData.write(to: dir.appendingPathComponent("widget-snapshot.json"))

    Schema.migrateWidgetSnapshotFiles(in: dir)

    // Old file should be deleted
    #expect(
      !FileManager.default.fileExists(
        atPath: dir.appendingPathComponent("widget-snapshot.json").path
      )
    )

    // Now-playing file should exist with correct data
    let npData = try Data(contentsOf: dir.appendingPathComponent("widget-now-playing.json"))
    let np = try JSONDecoder().decode(NowPlayingSnapshot.self, from: npData)
    #expect(np.schemaVersion == 1)
    #expect(np.nowPlaying?.episodeID == 42)
    #expect(np.nowPlaying?.episodeTitle == "Test Episode")
    #expect(np.nowPlaying?.artworkBase64 == nil)

    // Queue file should exist with correct data
    let qData = try Data(contentsOf: dir.appendingPathComponent("widget-queue.json"))
    let q = try JSONDecoder().decode(QueueSnapshot.self, from: qData)
    #expect(q.schemaVersion == 1)
    #expect(q.queue.count == 1)
    #expect(q.queue[0].episodeID == 100)
    #expect(q.queue[0].artworkURL == nil)
    #expect(q.artwork.isEmpty)
    #expect(q.queueTotalCount == 5)
  }

  @Test("skips gracefully when no legacy file exists")
  func skipsWhenNoLegacyFile() throws {
    let dir = try makeTempDir()

    Schema.migrateWidgetSnapshotFiles(in: dir)

    #expect(
      !FileManager.default.fileExists(
        atPath: dir.appendingPathComponent("widget-now-playing.json").path
      )
    )
    #expect(
      !FileManager.default.fileExists(
        atPath: dir.appendingPathComponent("widget-queue.json").path
      )
    )
  }

  @Test("handles legacy snapshot with nil nowPlaying")
  func handlesMinimalLegacySnapshot() throws {
    let dir = try makeTempDir()

    let legacy: [String: Any] = [
      "schemaVersion": 4,
      "queue": [] as [[String: Any]],
      "queueTotalCount": 0,
      "updatedAt": 1_700_000_000.0,
    ]
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    try legacyData.write(to: dir.appendingPathComponent("widget-snapshot.json"))

    Schema.migrateWidgetSnapshotFiles(in: dir)

    let npData = try Data(contentsOf: dir.appendingPathComponent("widget-now-playing.json"))
    let np = try JSONDecoder().decode(NowPlayingSnapshot.self, from: npData)
    #expect(np.nowPlaying == nil)
    #expect(np.schemaVersion == 1)

    // Old file should be deleted
    #expect(
      !FileManager.default.fileExists(
        atPath: dir.appendingPathComponent("widget-snapshot.json").path
      )
    )
  }
}
