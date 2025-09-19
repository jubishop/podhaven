// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeInformable: Identifiable, Searchable, Sendable, Stringable {
  var episodeID: Episode.ID? { get }
  var mediaGUID: MediaGUID { get }
  var title: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var description: String? { get }
  var queued: Bool { get }
  var queueOrder: Int? { get }
  var cacheStatus: Episode.CacheStatus { get }
  var started: Bool { get }
  var currentTime: CMTime { get }
  var finished: Bool { get }
}

extension EpisodeInformable {
  var episodeID: Episode.ID? { id as? Episode.ID }
}
