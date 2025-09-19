// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol EpisodeDisplayable: Gridable, Identifiable, Searchable, Sendable, Stringable {
  var episodeID: Episode.ID? { get }
  var mediaGUID: MediaGUID { get }
  var title: String { get }
  var podcastTitle: String { get }
  var pubDate: Date { get }
  var duration: CMTime { get }
  var image: URL { get }
  var description: String? { get }
  var queued: Bool { get }
  var queueOrder: Int? { get }
  var cacheStatus: CacheStatus { get }
  var started: Bool { get }
  var currentTime: CMTime { get }
  var finished: Bool { get }
}

extension EpisodeDisplayable {
  var episodeID: Episode.ID? { id as? Episode.ID }
}
