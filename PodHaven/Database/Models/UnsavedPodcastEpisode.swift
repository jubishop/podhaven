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
  var searchableString: String { unsavedEpisode.searchableString }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  // MARK: - Convenience Getters

  var image: URL { unsavedEpisode.image ?? unsavedPodcast.image }

  // MARK: - EpisodeDisplayable

  var mediaGUID: MediaGUID { unsavedEpisode.id }
  var title: String { unsavedEpisode.title }
  var pubDate: Date { unsavedEpisode.pubDate }
  var duration: CMTime { unsavedEpisode.duration }
  var cached: Bool { unsavedEpisode.cached }
  var caching: Bool { unsavedEpisode.caching }
  var started: Bool { unsavedEpisode.started }
  var completed: Bool { unsavedEpisode.completed }
  var queued: Bool { unsavedEpisode.queued }
  var queueOrder: Int? { unsavedEpisode.queueOrder }
  var description: String? { unsavedEpisode.description }
  var podcastTitle: String { unsavedPodcast.title }
}
