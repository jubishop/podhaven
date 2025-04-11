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
    let unfinishedMaxSQL = 
      "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = 0)"
    
    let unstartedMaxSQL = 
      "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = 0 " +
      "AND episode.currentTime = 0)"
    
    let unqueuedMaxSQL = 
      "(SELECT MAX(pubDate) FROM episode WHERE episode.podcastId = podcast.id AND episode.completed = 0 " +
      "AND episode.currentTime = 0 AND episode.queueOrder IS NULL)"
    
    return Podcast.all()
      .annotated(with: [
        SQL(sql: unfinishedMaxSQL).forKey("maxUnfinishedEpisodePubDate"),
        SQL(sql: unstartedMaxSQL).forKey("maxUnstartedEpisodePubDate"),
        SQL(sql: unqueuedMaxSQL).forKey("maxUnqueuedEpisodePubDate")
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
