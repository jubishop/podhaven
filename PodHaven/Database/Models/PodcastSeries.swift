// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastSeries: Decodable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArrayOf<Episode>
  let tags: IdentifiedArrayOf<Tag>?

  init(podcast: Podcast, episodes: [Episode] = [], tags: IdentifiedArrayOf<Tag>? = nil) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArrayOf(uniqueElements: episodes),
      tags: tags
    )
  }

  init(podcast: Podcast, episodes: IdentifiedArrayOf<Episode>, tags: IdentifiedArrayOf<Tag>? = nil)
  {
    self.podcast = podcast
    self.episodes = episodes
    self.tags = tags
  }

  // MARK: - Decodable

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    episodes = IdentifiedArrayOf(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes)
    )
    if let decodedTags = try container.decodeIfPresent([Tag].self, forKey: .tags) {
      tags = IdentifiedArrayOf(uniqueElements: decodedTags)
    } else {
      tags = nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case podcast
    case episodes
    case tags
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }
}
