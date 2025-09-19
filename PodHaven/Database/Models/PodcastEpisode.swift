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

  // MARK: - Stringable / Searchable

  var toString: String { episode.toString }
  var searchableString: String { episode.searchableString }

  // MARK: - Data

  let podcast: Podcast
  let episode: Episode

  // MARK: - Equatable

  static func == (lhs: PodcastEpisode, rhs: OnDeck) -> Bool { lhs.id == rhs.id }

  // MARK: - EpisodeDisplayable

  var mediaGUID: MediaGUID { episode.unsaved.id }
  var title: String { episode.title }
  var podcastTitle: String { podcast.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var image: URL { episode.image ?? podcast.image }
  var description: String? { episode.description }
  var currentTime: CMTime { episode.currentTime }
  var cacheStatus: CacheStatus { episode.cacheStatus }
  var started: Bool { episode.started }
  var finished: Bool { episode.finished }
  var queued: Bool { episode.queued }
  var queueOrder: Int? { episode.queueOrder }
}
