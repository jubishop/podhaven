// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

typealias PodcastSeriesArray = IdentifiedArray<FeedURL, PodcastSeries>

struct PodcastSeries: Decodable, FetchableRecord, Equatable, Identifiable, Hashable {
  var id: Podcast.ID { podcast.id }

  let podcast: Podcast
  let episodes: IdentifiedArray<GUID, Episode>

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: IdentifiedArray(id: \.guid))
  }

  init(podcast: Podcast, episodes: IdentifiedArray<GUID, Episode>) {
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
