// Copyright Justin Bishop, 2024 

import Foundation
import GRDB

struct PodcastSeries: Decodable, FetchableRecord, Equatable {
  let podcast: Podcast
  var episodes: Set<Episode>

  init(podcast: Podcast) {
    self.init(podcast: podcast, episodes: [])
  }

  init(podcast: Podcast, episodes: Set<Episode>) {
    self.podcast = podcast
    self.episodes = episodes
  }
}
