// Copyright Justin Bishop, 2025

import Foundation
import GRDB

@dynamicMemberLookup
struct PodcastWithLatestEpisodeDates:
  Decodable,
  Equatable,
  FetchableRecord,
  Identifiable,
  Stringable
{
  static func all() -> QueryInterfaceRequest<PodcastWithLatestEpisodeDates> {
    Podcast.all()
      .annotated(
        with: [
          Podcast.unfinishedEpisodes.forKey("unfinishedEpisode").max(Schema.pubDateColumn),
          Podcast.unstartedEpisodes.forKey("unstartedEpisode").max(Schema.pubDateColumn),
          Podcast.unqueuedEpisodes.forKey("unqueuedEpisode").max(Schema.pubDateColumn),
        ]
      )
      .asRequest(of: PodcastWithLatestEpisodeDates.self)
  }

  var id: Podcast.ID { podcast.id }
  var toString: String { podcast.toString }

  subscript<T>(dynamicMember keyPath: KeyPath<Podcast, T>) -> T {
    podcast[keyPath: keyPath]
  }

  let podcast: Podcast
  let maxUnfinishedEpisodePubDate: Date?
  let maxUnstartedEpisodePubDate: Date?
  let maxUnqueuedEpisodePubDate: Date?
}
