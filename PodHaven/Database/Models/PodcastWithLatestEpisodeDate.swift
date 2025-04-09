// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct PodcastWithLatestEpisodeDate: Decodable, Equatable, FetchableRecord {
  static let LatestEpisodeKey: String = "latestEpisodeDate"

  var podcast: Podcast
  var latestEpisodeDate: Date?
}
