// Copyright Justin Bishop, 2026

import Foundation

struct WidgetSnapshot: Codable, Sendable {
  static let currentSchemaVersion = 2

  struct NowPlaying: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let podcastTitle: String
    let pubDateTimestamp: Double
    let durationSeconds: Double
    let artworkBase64: String?
  }

  struct QueueItem: Codable, Sendable {
    let episodeID: Int64
    let episodeTitle: String
    let pubDateTimestamp: Double
    let durationSeconds: Double
    let artworkBase64: String?
  }

  let schemaVersion: Int
  let nowPlaying: NowPlaying?
  let queue: [QueueItem]
  let queueTotalCount: Int
  let skipForwardInterval: Int
  let skipBackwardInterval: Int
  let updatedAt: Date
}
