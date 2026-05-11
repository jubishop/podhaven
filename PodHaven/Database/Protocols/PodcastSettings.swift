// Copyright Justin Bishop, 2026

import Foundation

protocol PodcastSettings: Sendable {
  var defaultPlaybackRate: Double? { get }
  var queueAllEpisodes: QueueAllEpisodes { get }
  var cacheAllEpisodes: CacheAllEpisodes { get }
  var notifyNewEpisodes: Bool { get }
  var freshnessCadence: FreshnessCadence? { get }
}
