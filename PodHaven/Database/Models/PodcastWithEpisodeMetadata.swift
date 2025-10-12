// Copyright Justin Bishop, 2025

import Foundation
import GRDB

@dynamicMemberLookup
struct PodcastWithEpisodeMetadata:
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

  var id: FeedURL { podcast.feedURL }

  subscript<T>(dynamicMember keyPath: KeyPath<DisplayedPodcast, T>) -> T {
    podcast[keyPath: keyPath]
  }

  let podcast: DisplayedPodcast
  let episodeCount: Int
  let mostRecentEpisodeDate: Date?

  // MARK: - Custom Decoding

  enum CodingKeys: String, CodingKey, ColumnExpression {
    case episodeCount
    case mostRecentEpisodeDate
  }

  init(row: Row) throws {
    self.podcast = DisplayedPodcast(try Podcast(row: row))
    self.episodeCount = row[CodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[CodingKeys.mostRecentEpisodeDate]
  }
}
