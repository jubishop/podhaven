// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import Tagged
import UIKit

struct PodcastEpisode:
  Codable,
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
}
