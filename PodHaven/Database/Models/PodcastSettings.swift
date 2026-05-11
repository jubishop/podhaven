// Copyright Justin Bishop, 2026

import Foundation

struct PodcastSettings: Hashable, Sendable {
  var defaultPlaybackRate: Double?
  var queueAllEpisodes: QueueAllEpisodes
  var cacheAllEpisodes: CacheAllEpisodes
  var notifyNewEpisodes: Bool
  var freshnessCadence: FreshnessCadence?

  static let defaults = PodcastSettings(
    defaultPlaybackRate: nil,
    queueAllEpisodes: .never,
    cacheAllEpisodes: .never,
    notifyNewEpisodes: false,
    freshnessCadence: nil
  )
}
