// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct UnsavedPodcastEpisode:
  Codable,
  EpisodeDisplayable,
  Equatable,
  Hashable,
  Searchable,
  Stringable
{
  var id: MediaGUID { unsavedEpisode.id }

  // MARK: - Stringable / Searchable

  var toString: String { unsavedEpisode.toString }
  var searchableString: String {
    "\(unsavedPodcast.searchableString) - \(unsavedEpisode.searchableString)"
  }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  // MARK: - EpisodeDisplayable

  var feedURL: FeedURL { unsavedPodcast.feedURL }
  var podcastTitle: String { unsavedPodcast.title }
  var image: URL { unsavedEpisode.image ?? unsavedPodcast.image }
  var podcastImage: URL { unsavedPodcast.image }
  var saveInCache: Bool { unsavedEpisode.saveInCache }

  // MARK: - EpisodeInformable

  var mediaGUID: MediaGUID { unsavedEpisode.id }
  var title: String { unsavedEpisode.title }
  var pubDate: Date { unsavedEpisode.pubDate }
  var description: String? { unsavedEpisode.description }
  var duration: CMTime { unsavedEpisode.duration }
  var currentTime: CMTime { unsavedEpisode.currentTime }
  var queueDate: Date? { unsavedEpisode.queueDate }
  var queueOrder: Int? { unsavedEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { unsavedEpisode.cacheStatus }
  var finishDate: Date? { unsavedEpisode.finishDate }

  // MARK: - Reset

  func toOriginalUnsavedPodcastEpisode() throws -> UnsavedPodcastEpisode {
    UnsavedPodcastEpisode(
      unsavedPodcast: try unsavedPodcast.toOriginalUnsavedPodcast(),
      unsavedEpisode: try unsavedEpisode.toOriginalUnsavedEpisode()
    )
  }
}
