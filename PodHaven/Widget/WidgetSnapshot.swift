// Copyright Justin Bishop, 2026

import Foundation

struct WidgetSnapshot: Codable, Sendable {
  static let currentSchemaVersion = 1

  struct NowPlaying: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let podcastTitle: String
    let durationSeconds: Double
    let currentTimeSeconds: Double
    let playbackStatus: String
    let artworkBase64: String?
  }

  struct QueueItem: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let podcastTitle: String
    let durationSeconds: Double
  }

  let schemaVersion: Int
  let nowPlaying: NowPlaying?
  let queue: [QueueItem]
  let updatedAt: Date
}
