// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Logging

extension Schema {
  // Note: the widget extension may refresh before the app runs this migration,
  // briefly showing empty widgets until the user opens the app. This is acceptable
  // — the window is short, the .empty states are designed for it, and adding a
  // fallback reader for the legacy file isn't worth the complexity.
  static func migrateV30(_: Database) throws {
    guard
      let containerURL = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: AppInfo.appGroupID
      )
    else {
      log.warning("v30: app group container not found, skipping widget snapshot migration")
      return
    }
    migrateWidgetSnapshotFiles(in: containerURL)
  }

  // MARK: - v30: Widget Snapshot File Migration

  // Splits the monolithic widget-snapshot.json into per-widget files.
  // Artwork is not migrated — it will be populated on the next writer cycle.
  static func migrateWidgetSnapshotFiles(in containerURL: URL) {
    let oldURL = containerURL.appendingPathComponent("widget-snapshot.json")
    guard FileManager.default.fileExists(atPath: oldURL.path) else {
      log.debug("v30: no legacy widget-snapshot.json, nothing to migrate")
      return
    }

    struct LegacySnapshot: Codable {
      struct NowPlaying: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let podcastTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
      }
      struct QueueItem: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
      }
      let nowPlaying: NowPlaying?
      let queue: [QueueItem]
      let queueTotalCount: Int
      let updatedAt: Date
    }

    // Self-contained output structs frozen to today's schema (version 1).
    // These must never reference the live snapshot types so the migration
    // stays stable if the types evolve later.
    struct V1NowPlaying: Codable {
      struct NowPlaying: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let podcastTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
        let artworkBase64: String?
      }
      let schemaVersion: Int
      let nowPlaying: NowPlaying?
      let updatedAt: Date
    }
    struct V1Queue: Codable {
      struct QueueItem: Codable {
        let episodeID: Int64
        let episodeTitle: String
        let pubDateTimestamp: Double
        let durationSeconds: Double
        let artworkURL: String?
      }
      let schemaVersion: Int
      let queue: [QueueItem]
      let queueTotalCount: Int
      let artwork: [String: String]
      let updatedAt: Date
    }

    do {
      let data = try Data(contentsOf: oldURL)
      let legacy = try JSONDecoder().decode(LegacySnapshot.self, from: data)
      let now = legacy.updatedAt

      let nowPlayingSnapshot = V1NowPlaying(
        schemaVersion: 1,
        nowPlaying: legacy.nowPlaying.map {
          V1NowPlaying.NowPlaying(
            episodeID: $0.episodeID,
            episodeTitle: $0.episodeTitle,
            podcastTitle: $0.podcastTitle,
            pubDateTimestamp: $0.pubDateTimestamp,
            durationSeconds: $0.durationSeconds,
            artworkBase64: nil
          )
        },
        updatedAt: now
      )
      try JSONEncoder().encode(nowPlayingSnapshot)
        .write(to: containerURL.appendingPathComponent("widget-now-playing.json"))

      let queueSnapshot = V1Queue(
        schemaVersion: 1,
        queue: legacy.queue.map {
          V1Queue.QueueItem(
            episodeID: $0.episodeID,
            episodeTitle: $0.episodeTitle,
            pubDateTimestamp: $0.pubDateTimestamp,
            durationSeconds: $0.durationSeconds,
            artworkURL: nil
          )
        },
        queueTotalCount: legacy.queueTotalCount,
        artwork: [:],
        updatedAt: now
      )
      try JSONEncoder().encode(queueSnapshot)
        .write(to: containerURL.appendingPathComponent("widget-queue.json"))

      try FileManager.default.removeItem(at: oldURL)
      log.info("v30: migrated widget-snapshot.json to per-widget files")
    } catch {
      log.caughtError("v30: failed to migrate widget snapshot", error)
    }
  }
}
