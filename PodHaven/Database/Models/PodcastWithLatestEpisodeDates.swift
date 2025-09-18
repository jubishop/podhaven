// Copyright Justin Bishop, 2025

import Foundation
import GRDB

@dynamicMemberLookup
struct PodcastWithLatestEpisodeDates:
  Decodable,
  Equatable,
  FetchableRecord,
  Identifiable,
  Searchable,
  Stringable
{

  // MARK: - Annotation Queries

  static let unfinishedEpisodes = Podcast.episodesSubquery.unfinished()
  static let unstartedEpisodes = unfinishedEpisodes.unstarted()
  static let unqueuedEpisodes = unstartedEpisodes.unqueued()

  // MARK: - QueryInterfaceRequest

  static func all() -> QueryInterfaceRequest<PodcastWithLatestEpisodeDates> {
    Podcast.all()
      .annotated(with: [
        unfinishedEpisodes.maxPubDate().forKey(CodingKeys.maxUnfinishedEpisodePubDate),
        unstartedEpisodes.maxPubDate().forKey(CodingKeys.maxUnstartedEpisodePubDate),
        unqueuedEpisodes.maxPubDate().forKey(CodingKeys.maxUnqueuedEpisodePubDate),
      ])
      .asRequest(of: PodcastWithLatestEpisodeDates.self)
  }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }

  // MARK: - Data

  var id: Podcast.ID { podcast.id }

  subscript<T>(dynamicMember keyPath: KeyPath<Podcast, T>) -> T {
    podcast[keyPath: keyPath]
  }

  let podcast: Podcast
  let maxUnfinishedEpisodePubDate: Date?
  let maxUnstartedEpisodePubDate: Date?
  let maxUnqueuedEpisodePubDate: Date?
}
