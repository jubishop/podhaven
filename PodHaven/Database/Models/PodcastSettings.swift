// Copyright Justin Bishop, 2026

import Foundation

struct PodcastSettings: Hashable, Sendable {
  var defaultPlaybackRate: Double?
  var queueAllEpisodes: QueueAllEpisodes
  var autoQueueLimit: Int?
  var cacheAllEpisodes: CacheAllEpisodes
  var notifyNewEpisodes: Bool
  var freshnessCadence: FreshnessCadence?

  static let autoQueueLimitRange = 1...5
  static let defaultAutoQueueLimit = 3

  static let defaults = PodcastSettings(
    defaultPlaybackRate: nil,
    queueAllEpisodes: .never,
    autoQueueLimit: nil,
    cacheAllEpisodes: .never,
    notifyNewEpisodes: false,
    freshnessCadence: nil
  )
}
