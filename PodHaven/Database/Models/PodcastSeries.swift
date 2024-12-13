// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OrderedCollections

struct PodcastSeries: Decodable, FetchableRecord, Equatable {
  let podcast: Podcast
  let episodes: [Episode]
  private let episodesDictionary: OrderedDictionary<String, Episode>

  enum CodingKeys: String, CodingKey {
    case podcast
    case episodes
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let podcast = try values.decode(Podcast.self, forKey: .podcast)
    let episodes = try values.decode([Episode].self, forKey: .episodes)
    self.init(podcast: podcast, episodes: episodes)
  }

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: [])
  }

  init(podcast: Podcast, episodes: [Episode]) {
    self.podcast = podcast
    self.episodes = episodes
    self.episodesDictionary = OrderedDictionary(
      uniqueKeysWithValues: episodes.map { ($0.guid, $0) }
    )
  }
}
