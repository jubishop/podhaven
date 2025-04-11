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
    let unfinishedSQL = SQL(
      sql:
        "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = ?)",
      arguments: [false]
    )

    let unstartedSQL = SQL(
      sql:
        "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = ? AND episode.currentTime = ?)",
      arguments: [false, 0]
    )

    let unqueuedSQL = SQL(
      sql:
        "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = ? AND episode.currentTime = ? AND episode.queueOrder IS ?)",
      arguments: [false, 0, nil]
    )

    return Podcast.all()
      .annotated(with: [
        unfinishedSQL.forKey("maxUnfinishedEpisodePubDate"),
        unstartedSQL.forKey("maxUnstartedEpisodePubDate"),
        unqueuedSQL.forKey("maxUnqueuedEpisodePubDate"),
      ])
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
