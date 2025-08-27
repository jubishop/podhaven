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
  EpisodeFilterable,
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

  // MARK: - Convenience Getters

  var image: URL { episode.image ?? podcast.image }

  // MARK: - EpisodeDisplayable // EpisodeFilterable

  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var cached: Bool { episode.cached }
  var started: Bool { episode.started }
  var completed: Bool { episode.completed }
  var queued: Bool { episode.queued }
}
