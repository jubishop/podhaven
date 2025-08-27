// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct UnsavedPodcastEpisode:
  Codable,
  Equatable,
  Hashable,
  Identifiable,
  PodcastEpisodeDisplayable,
  Searchable,
  Stringable
{
  var id: MediaURL { unsavedEpisode.media }

  // MARK: - Stringable / Searchable

  var toString: String { unsavedEpisode.toString }
  var searchableString: String { unsavedEpisode.searchableString }

  // MARK: - Data

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  // MARK: - Convenience Getters

  var image: URL { unsavedEpisode.image ?? unsavedPodcast.image }

  // MARK: - PodcastEpisodeDisplayable

  var title: String { unsavedEpisode.title }
  var pubDate: Date { unsavedEpisode.pubDate }
  var duration: CMTime { unsavedEpisode.duration }
  var cached: Bool { unsavedEpisode.cached }
  var completed: Bool { false }
  var queued: Bool { unsavedEpisode.queued }
}
