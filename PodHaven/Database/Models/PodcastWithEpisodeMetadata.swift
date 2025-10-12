// Copyright Justin Bishop, 2025

import Foundation
import GRDB

@dynamicMemberLookup
struct PodcastWithEpisodeMetadata:
  Decodable,
  Equatable,
  FetchableRecord,
  Identifiable,
  Searchable,
  Stringable
{

  // MARK: - QueryInterfaceRequest

  static func all() -> QueryInterfaceRequest<PodcastWithEpisodeMetadata> {
    Podcast.all()
      .annotated(with: [
        Podcast.episodes.count.forKey(CodingKeys.episodeCount),
        Podcast.episodes.max(\.pubDate).forKey(CodingKeys.mostRecentEpisodeDate),
      ])
      .asRequest(of: PodcastWithEpisodeMetadata.self)
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
  let episodeCount: Int
  let mostRecentEpisodeDate: Date?
}
