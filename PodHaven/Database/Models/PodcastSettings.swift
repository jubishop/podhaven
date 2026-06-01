// Copyright Justin Bishop, 2026

import Foundation

struct PodcastSettings: Hashable, Sendable {
  var defaultPlaybackRate: Double?
  var queueAllEpisodes: QueueAllEpisodes
  var queueLimit: Int?
  var cacheAllEpisodes: CacheAllEpisodes
  var notifyNewEpisodes: Bool
  var freshnessCadence: FreshnessCadence?

  static let queueLimitRange = 1...5
  static let defaultQueueLimit = 3

  static let defaults = PodcastSettings(
    defaultPlaybackRate: nil,
    queueAllEpisodes: .never,
    queueLimit: nil,
    cacheAllEpisodes: .never,
    notifyNewEpisodes: false,
    freshnessCadence: nil
  )
}
