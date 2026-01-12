// Copyright Justin Bishop, 2025

import Foundation

protocol PodcastDisplayable:
  Hashable,
  Searchable,
  Sendable,
  Stringable
where ID: Sendable {
  var podcastID: Podcast.ID? { get }

  var feedURL: FeedURL { get }
  var image: URL { get }
  var title: String { get }
  var description: String { get }
  var link: URL? { get }
  var subscriptionDate: Date? { get }
  var defaultPlaybackRate: Double? { get }
  var queueAllEpisodes: QueueAllEpisodes { get }
  var cacheAllEpisodes: CacheAllEpisodes { get }
  var notifyNewEpisodes: Bool { get }

  var isSaved: Bool { get }
  var subscribed: Bool { get }
}

extension PodcastDisplayable {
  var podcastID: Podcast.ID? { id as? Podcast.ID }
  var isSaved: Bool { podcastID != nil }
  var subscribed: Bool { subscriptionDate != nil }
}
