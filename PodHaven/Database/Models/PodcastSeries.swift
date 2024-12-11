// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct PodcastSeries: Decodable, FetchableRecord, Equatable {
  let podcast: Podcast
  var episodes: [Episode]

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: [])
  }

  init(podcast: Podcast, episodes: [Episode]) {
    self.podcast = podcast
    self.episodes = episodes
  }
}
