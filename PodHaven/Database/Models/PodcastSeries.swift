// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastSeries: Decodable, FetchableRecord, Equatable {
  let podcast: Podcast
  let episodes: IdentifiedArray<String, Episode>

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: IdentifiedArray(id: \Episode.guid))
  }

  init(podcast: Podcast, episodes: IdentifiedArray<String, Episode>) {
    self.podcast = podcast
    self.episodes = episodes
  }

  // MARK: - Decodable

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    episodes = IdentifiedArray(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes),
      id: \Episode.guid
    )
  }

  private enum CodingKeys: String, CodingKey {
    case podcast, episodes
  }
}
