// Copyright Justin Bishop, 2025

import Foundation
import GRDB

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
  let tagIDs: Set<Tag.ID>

  // Resolved cadence for saved podcasts, mirroring
  // `RecommendationRepo.resolveFreshnessCadences`: manual override else the
  // cached inference. `nil` for unsaved rows (search results), whose query path
  // never selects these columns — those fall back to the plain date icon.
  let resolvedFreshnessCadence: FreshnessCadence?

  // MARK: - Initialization

  init(
    podcast: PodcastType,
    episodeCount: Int,
    mostRecentEpisodeDate: Date?,
    tagIDs: Set<Tag.ID> = [],
    resolvedFreshnessCadence: FreshnessCadence? = nil
  ) {
    self.podcast = podcast
    self.episodeCount = episodeCount
    self.mostRecentEpisodeDate = mostRecentEpisodeDate
    self.tagIDs = tagIDs
    self.resolvedFreshnessCadence = resolvedFreshnessCadence
  }
}

// MARK: - FetchableRecord

extension PodcastWithEpisodeMetadata: FetchableRecord
where PodcastType: FetchableRecord & TableRecord {
  init(row: Row) throws {
    self.podcast = try PodcastType(row: row)
    self.episodeCount = row[CodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[CodingKeys.mostRecentEpisodeDate]
    self.tagIDs = try PodcastTag.decodeTagIDs(from: row)
    let manual: FreshnessCadence? = row[Podcast.Columns.freshnessCadence]
    let inferred: FreshnessCadence? = row[Podcast.Columns.inferredFreshnessCadence]
    self.resolvedFreshnessCadence = manual ?? inferred
  }

  enum CodingKeys: String, CodingKey, ColumnExpression {
    case episodeCount
    case mostRecentEpisodeDate
  }

  // MARK: Query Builders

  static func all(
    _ filter: PodcastFilter = { $0 }
  ) -> QueryInterfaceRequest<PodcastWithEpisodeMetadata> {
    let selection =
      PodcastType.databaseSelection + [
        Podcast.Columns.freshnessCadence,
        Podcast.Columns.inferredFreshnessCadence,
        PodcastTag.tagIDsSelectable,
      ]
    return filter(Podcast.all().select(selection))
      .annotated(with: [
        Podcast.episodes.count.forKey(CodingKeys.episodeCount),
        Podcast.episodes.max(\.pubDate).forKey(CodingKeys.mostRecentEpisodeDate),
      ])
      .asRequest(of: PodcastWithEpisodeMetadata.self)
  }
}
