// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

struct PodcastSeries: Decodable, Equatable, FetchableRecord, Hashable, Identifiable, Stringable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArray<MediaGUID, Episode>

  init(podcast: Podcast, episodes: [Episode] = []) {
    self.init(
      podcast: podcast,
      episodes: IdentifiedArray(uniqueElements: episodes, id: \.unsaved.id)
    )
  }

  init(podcast: Podcast, episodes: IdentifiedArray<MediaGUID, Episode>) {
    self.podcast = podcast
    self.episodes = episodes
  }

  // MARK: - Decodable

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    podcast = try container.decode(Podcast.self, forKey: .podcast)
    episodes = IdentifiedArray(
      uniqueElements: try container.decode([Episode].self, forKey: .episodes),
      id: \.unsaved.id
    )
  }

  private enum CodingKeys: String, CodingKey {
    case podcast, episodes
  }

  // MARK: - Stringable

  var toString: String { podcast.toString }
}
