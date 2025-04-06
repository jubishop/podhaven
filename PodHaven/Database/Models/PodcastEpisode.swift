// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections
import Tagged

struct PodcastEpisode: Codable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Episode.ID { episode.id }

  // MARK: - Stringable

  var toString: String { episode.title }

  // MARK: - Data

  let podcast: Podcast
  let episode: Episode
}
