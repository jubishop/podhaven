// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastDisplayable: PodcastListable {
  var description: String { get }
  var link: URL? { get }
  var defaultPlaybackRate: Double? { get }
  var queueAllEpisodes: QueueAllEpisodes { get }
  var cacheAllEpisodes: CacheAllEpisodes { get }
  var notifyNewEpisodes: Bool { get }
  var freshnessHalfLifeDays: Int? { get }
}
