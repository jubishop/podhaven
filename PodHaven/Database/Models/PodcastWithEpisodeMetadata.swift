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

  // MARK: - Data

  let displayedPodcast: DisplayedPodcast
  let episodeCount: Int
  let mostRecentEpisodeDate: Date?

  // MARK: - Getters

  var isSaved: Bool { displayedPodcast.getPodcast() != nil }
  subscript<T>(dynamicMember keyPath: KeyPath<DisplayedPodcast, T>) -> T {
    displayedPodcast[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: FeedURL { displayedPodcast.feedURL }

  // MARK: - Stringable / Searchable

  var toString: String { displayedPodcast.toString }
  var searchableString: String { displayedPodcast.searchableString }

  // MARK: - Custom Decoding

  enum CodingKeys: String, CodingKey, ColumnExpression {
    case episodeCount
    case mostRecentEpisodeDate
  }

  init(row: Row) throws {
    self.displayedPodcast = DisplayedPodcast(try Podcast(row: row))
    self.episodeCount = row[CodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[CodingKeys.mostRecentEpisodeDate]
  }
}
