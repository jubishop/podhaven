// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct PodcastWithLatestEpisodeDates: Decodable, Equatable, FetchableRecord {
  // TODO: How to infer this?
  enum CodingKeys: String, CodingKey {
    case podcast
    case latestUnfinishedEpisodeDate
    case latestUnstartedEpisodeDate
    case latestUnqueuedEpisodeDate
  }

  let podcast: Podcast
  let latestUnfinishedEpisodeDate: Date?
  let latestUnstartedEpisodeDate: Date?
  let latestUnqueuedEpisodeDate: Date?
}
