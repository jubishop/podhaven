// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation

protocol EpisodeFoundational: Identifiable, Sendable, Stringable where ID: Sendable {
  // MARK: - Core Properties

  var episodeID: Episode.ID? { get }
  var mediaGUID: MediaGUID { get }
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }

  // MARK: - User Properties

  var queueOrder: Int? { get }
  var cacheStatus: Episode.CacheStatus { get }
  var saveInCache: Bool { get }
  var currentTime: CMTime { get }
  var finishDate: Date? { get }

  // MARK: - Computed Properties

  var isSaved: Bool { get }
  var queued: Bool { get }
  var started: Bool { get }
  var finished: Bool { get }
}

// MARK: - Default Implementations

extension EpisodeFoundational {
  var episodeID: Episode.ID? { id as? Episode.ID }

  var isSaved: Bool { episodeID != nil }
  var queued: Bool { queueOrder != nil }
  var started: Bool { currentTime.seconds > 0 }
  var finished: Bool { finishDate != nil }

  // MARK: - Stringable

  var toString: String { "[\(id)] - (\(mediaGUID)) - \(title)" }
}
