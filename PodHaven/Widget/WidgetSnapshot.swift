// Copyright Justin Bishop, 2026

import Foundation

struct WidgetSnapshot: Codable, Sendable {
  static let currentSchemaVersion = 1

  struct NowPlaying: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let podcastTitle: String
    let durationSeconds: Double
    let playbackStatus: PlaybackStatus
    let artworkBase64: String?
  }

  struct QueueItem: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let durationSeconds: Double
    let artworkBase64: String?
  }

  let schemaVersion: Int
  let loadingTitle: String?
  let nowPlaying: NowPlaying?
  let queue: [QueueItem]
  let queueTotalCount: Int
  let updatedAt: Date
}
