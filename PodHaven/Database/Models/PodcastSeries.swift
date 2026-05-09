// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

// Operational shape used by RefreshManager and series writers. Carries
// full `Episode` rows for feed merge / migration. Detail-view callers
// should use `PodcastSeriesDetail` instead — it carries tag IDs and the
// slim listable-episode shape.
struct PodcastSeries: Decodable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArrayOf<Episode>

  init(
    podcast: Podcast,
    episodes: [Episode] = []
  ) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArrayOf(uniqueElements: episodes)
    )
  }

  init(
    podcast: Podcast,
    episodes: IdentifiedArrayOf<Episode>
  ) {
    self.podcast = podcast
    self.episodes = episodes
  }

  // MARK: - Decodable

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    episodes = IdentifiedArrayOf(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes)
    )
  }

  private enum CodingKeys: String, CodingKey {
    case podcast
    case episodes
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }
}
