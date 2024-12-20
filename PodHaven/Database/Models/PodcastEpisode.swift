// Copyright Justin Bishop, 2024

import Foundation
import GRDB

struct PodcastEpisode: Codable, FetchableRecord, Equatable {
  let podcast: Podcast
  let episode: Episode
}
