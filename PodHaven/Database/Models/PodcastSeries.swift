// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OrderedCollections

struct PodcastSeries: Decodable, FetchableRecord, Equatable {
  let podcast: Podcast
  let episodes: [Episode]
  lazy var episodesDictionary: OrderedDictionary<String, Episode> = {
    return OrderedDictionary(
      uniqueKeysWithValues: episodes.map { ($0.guid, $0) }
    )
  }()

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: [])
  }

  init(podcast: Podcast, episodes: [Episode]) {
    self.podcast = podcast
    self.episodes = episodes
  }
}
