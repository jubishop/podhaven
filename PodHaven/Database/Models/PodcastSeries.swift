// Copyright Justin Bishop, 2024 

import Foundation
import GRDB

struct PodcastSeries: Decodable, FetchableRecord {
  let podcast: Podcast
  var episodes: Set<Episode>
}
