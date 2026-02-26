// Copyright Justin Bishop, 2026

import Foundation

enum WidgetPlaybackStatus: String, Codable, Sendable {
  case loading, paused, playing, stopped, waiting

  var isPlaying: Bool { self == .playing }
}

struct WidgetSnapshot: Codable, Sendable {
  static let currentSchemaVersion = 1

  struct NowPlaying: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let podcastTitle: String
    let durationSeconds: Double
    let currentTimeSeconds: Double
    let playbackStatus: WidgetPlaybackStatus
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
  let queueTotalCount: Int
  let updatedAt: Date
}
