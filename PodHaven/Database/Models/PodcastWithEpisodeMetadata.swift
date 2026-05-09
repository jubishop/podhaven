// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import IdentifiedCollections

@dynamicMemberLookup
struct PodcastWithEpisodeMetadata<PodcastType: PodcastListable>: Searchable, Stringable {
  // MARK: - Getters

  subscript<T>(dynamicMember keyPath: KeyPath<PodcastType, T>) -> T {
    podcast[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: PodcastType.ID { podcast.id }

  // MARK: - Stringable / Searchable

  var toString: String { podcast.toString }
  var searchableString: String { podcast.searchableString }

  // MARK: - Data

  let podcast: PodcastType
  let episodeCount: Int
  let mostRecentEpisodeDate: Date?
  let tags: IdentifiedArrayOf<Tag>

  // MARK: - Initialization

  init(
    podcast: PodcastType,
    episodeCount: Int,
    mostRecentEpisodeDate: Date?,
    tags: IdentifiedArrayOf<Tag> = []
  ) {
    self.podcast = podcast
    self.episodeCount = episodeCount
    self.mostRecentEpisodeDate = mostRecentEpisodeDate
    self.tags = tags
  }
}

// MARK: - FetchableRecord

extension PodcastWithEpisodeMetadata: FetchableRecord
where PodcastType: FetchableRecord & TableRecord {
  init(row: Row) throws {
    self.podcast = try PodcastType(row: row)
    self.episodeCount = row[CodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[CodingKeys.mostRecentEpisodeDate]
    let tagRows = row.prefetchedRows[Self.tagsKey] ?? []
    self.tags = IdentifiedArrayOf(uniqueElements: try tagRows.map { try Tag(row: $0) })
  }

  enum CodingKeys: String, CodingKey, ColumnExpression {
    case episodeCount
    case mostRecentEpisodeDate
  }

  fileprivate static var tagsKey: String { "tags" }

  // MARK: Query Builders

  // Selects from the Podcast table but narrows columns to whatever the
  // generic PodcastType declares in its `databaseSelection`. For
  // `PodcastWithEpisodeMetadata<Podcast>` this defaults to all columns; for
  // `PodcastWithEpisodeMetadata<ListablePodcast>` it picks up the listable
  // subset automatically — no need for callers to pass columns explicitly.
  static func all(
    _ filter: PodcastFilter = { $0 }
  ) -> QueryInterfaceRequest<PodcastWithEpisodeMetadata> {
    filter(Podcast.all().select(PodcastType.databaseSelection))
      .annotated(with: [
        Podcast.episodes.count.forKey(CodingKeys.episodeCount),
        Podcast.episodes.max(\.pubDate).forKey(CodingKeys.mostRecentEpisodeDate),
      ])
      .including(all: Podcast.tags.order { $0.name.collating(.nocase) })
      .asRequest(of: PodcastWithEpisodeMetadata.self)
  }
}
