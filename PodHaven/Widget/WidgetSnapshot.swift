// Copyright Justin Bishop, 2026

import Foundation

protocol WidgetSnapshotType: Codable, Sendable {
  static var currentSchemaVersion: Int { get }
  var schemaVersion: Int { get }
}

// MARK: - Now Playing

struct NowPlayingSnapshot: WidgetSnapshotType {
  static let currentSchemaVersion = 1

  struct NowPlaying: Codable, Sendable {
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

// MARK: - Queue

struct QueueSnapshot: WidgetSnapshotType {
  static let currentSchemaVersion = 1

  struct QueueItem: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let pubDateTimestamp: Double
    let durationSeconds: Double
    let artworkURL: String?
  }

  let schemaVersion: Int
  let queue: [QueueItem]
  let queueTotalCount: Int
  // Inline artwork dictionary keyed by image URL string → base64.
  // Deduplicates artwork when multiple episodes share a podcast image.
  let artwork: [String: String]
  let updatedAt: Date
}
