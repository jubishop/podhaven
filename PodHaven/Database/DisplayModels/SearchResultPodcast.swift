// Copyright Justin Bishop, 2025

import Foundation

struct SearchResultPodcast:
  PodcastDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  let resultFeedURL: FeedURL
  let podcast: Podcast

  // MARK: - Identifiable

  var id: FeedURL { resultFeedURL }

  // MARK: - PodcastDisplayable

  var podcastID: Podcast.ID? { podcast.podcastID }
  var feedURL: FeedURL { podcast.feedURL }
  var iTunesID: ITunesPodcastID? { podcast.iTunesID }
  var image: URL { podcast.image }
  var title: String { podcast.title }
  var description: String { podcast.description }
  var link: URL? { podcast.link }
  var subscriptionDate: Date? { podcast.subscriptionDate }
  var defaultPlaybackRate: Double? { podcast.defaultPlaybackRate }
  var queueAllEpisodes: QueueAllEpisodes { podcast.queueAllEpisodes }
  var cacheAllEpisodes: CacheAllEpisodes { podcast.cacheAllEpisodes }
  var notifyNewEpisodes: Bool { podcast.notifyNewEpisodes }

  // MARK: - Hashable / Equatable
  // Intentionally hashes/compares on the canonical podcast, not resultFeedURL.
  // id (resultFeedURL) drives IdentifiedArray slot identity; hash/equality answer
  // "is this the same underlying podcast data?" so SwiftUI diffing re-renders when
  // the podcast changes, not when the search slot does.

  func hash(into hasher: inout Hasher) {
    hasher.combine(podcast)
  }

  static func == (lhs: SearchResultPodcast, rhs: SearchResultPodcast) -> Bool {
    lhs.podcast == rhs.podcast
  }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }
}
