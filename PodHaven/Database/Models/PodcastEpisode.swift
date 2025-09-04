// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import GRDB
import IdentifiedCollections
import Tagged
import UIKit

struct PodcastEpisode:
  Codable,
  EpisodeDisplayable,
  Equatable,
  FetchableRecord,
  Hashable,
  Identifiable,
  Searchable,
  Stringable
{
  var id: Episode.ID { episode.id }

  // MARK: - Stringable

  var toString: String { episode.toString }

  // MARK: - Searchable

  var searchableString: String { episode.searchableString }

  // MARK: - Data

  let podcast: Podcast
  let episode: Episode

  // MARK: - Equatable

  static func == (lhs: PodcastEpisode, rhs: OnDeck) -> Bool { lhs.id == rhs.id }

  // MARK: - EpisodeDisplayable

  var mediaGUID: MediaGUID { episode.unsaved.id }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var image: URL { episode.image ?? podcast.image }
  var cached: Bool { episode.cached }
  var caching: Bool { episode.caching }
  var started: Bool { episode.started }
  var completed: Bool { episode.completed }
  var queued: Bool { episode.queued }
  var description: String? { episode.description }
  var podcastTitle: String { podcast.title }
}
