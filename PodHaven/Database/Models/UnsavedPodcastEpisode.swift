// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct UnsavedPodcastEpisode:
  Codable,
  EpisodeDisplayable,
  Equatable,
  Hashable,
  Identifiable,
  Searchable,
  Stringable
{
  var id: MediaGUID { unsavedEpisode.id }

  // MARK: - Stringable / Searchable

  var toString: String { unsavedEpisode.toString }
  var searchableString: String { "\(unsavedPodcast.searchableString) - \(unsavedEpisode.searchableString)" }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  // MARK: - EpisodeDisplayable

  var mediaGUID: MediaGUID { unsavedEpisode.id }
  var title: String { unsavedEpisode.title }
  var podcastTitle: String { unsavedPodcast.title }
  var pubDate: Date { unsavedEpisode.pubDate }
  var duration: CMTime { unsavedEpisode.duration }
  var image: URL { unsavedEpisode.image ?? unsavedPodcast.image }
  var description: String? { unsavedEpisode.description }
  var queued: Bool { unsavedEpisode.queued }
  var queueOrder: Int? { unsavedEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { unsavedEpisode.cacheStatus }
  var started: Bool { unsavedEpisode.started }
  var currentTime: CMTime { unsavedEpisode.currentTime }
  var finished: Bool { unsavedEpisode.finished }
}
