// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastDisplayable: PodcastListable, Hashable {
  var iTunesID: ITunesPodcastID? { get }
  var link: URL? { get }
  var defaultPlaybackRate: Double? { get }
  var queueAllEpisodes: QueueAllEpisodes { get }
  var cacheAllEpisodes: CacheAllEpisodes { get }
  var notifyNewEpisodes: Bool { get }
}

extension PodcastDisplayable {
  var iTunesID: ITunesPodcastID? { nil }
}
