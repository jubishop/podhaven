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
    let podcastTable = TableAlias()

    let unfinishedSubquery =
      Episode
      .select(max(Schema.pubDateColumn))
      .filter(Schema.podcastIDColumn == podcastTable[Schema.idColumn])
      .filter(Schema.completedColumn == false)

    let unstartedSubquery =
      Episode
      .select(max(Schema.pubDateColumn))
      .filter(Schema.podcastIDColumn == podcastTable[Schema.idColumn])
      .filter(Schema.completedColumn == false)
      .filter(Schema.currentTimeColumn == 0)

    let unqueuedSubquery =
      Episode
      .select(max(Schema.pubDateColumn))
      .filter(Schema.podcastIDColumn == podcastTable[Schema.idColumn])
      .filter(Schema.completedColumn == false)
      .filter(Schema.currentTimeColumn == 0)
      .filter(Schema.queueOrderColumn == nil)

    return Podcast.aliased(podcastTable).all()
      .annotated(with: [
        unfinishedSubquery.forKey(CodingKeys.maxUnfinishedEpisodePubDate),
        unstartedSubquery.forKey(CodingKeys.maxUnstartedEpisodePubDate),
        unqueuedSubquery.forKey(CodingKeys.maxUnqueuedEpisodePubDate),
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
