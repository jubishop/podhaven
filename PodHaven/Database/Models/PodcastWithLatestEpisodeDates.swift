// Copyright Justin Bishop, 2025

import Foundation
import GRDB

struct PodcastWithLatestEpisodeDates: Decodable, Equatable, FetchableRecord {
  static func all(_ sqlExpression: SQLExpression? = nil) -> QueryInterfaceRequest<
    PodcastWithLatestEpisodeDates
  > {
    Podcast.all()
      .filtered(with: sqlExpression)
      .annotated(
        with: [
          Podcast.unfinishedEpisodes.forKey("unfinishedEpisode").max(Schema.pubDateColumn),
          Podcast.unstartedEpisodes.forKey("unstartedEpisode").max(Schema.pubDateColumn),
          Podcast.unqueuedEpisodes.forKey("unqueuedEpisode").max(Schema.pubDateColumn),
        ]
      )
      .asRequest(of: PodcastWithLatestEpisodeDates.self)
  }

  let podcast: Podcast
  let maxUnfinishedEpisodePubDate: Date?
  let maxUnstartedEpisodePubDate: Date?
  let maxUnqueuedEpisodePubDate: Date?
}
