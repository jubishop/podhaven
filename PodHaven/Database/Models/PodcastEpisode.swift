// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct PodcastEpisode: Codable, FetchableRecord, Equatable, Identifiable {
  var id: Int64 { episode.id }

  let podcast: Podcast
  let episode: Episode
}
