// Copyright Justin Bishop, 2025

import Foundation
import GRDB

enum PodcastMetadataCodingKeys: String, CodingKey, ColumnExpression {
  case episodeCount
  case mostRecentEpisodeDate
}

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

  // MARK: - Initialization

  init(podcast: PodcastType, episodeCount: Int, mostRecentEpisodeDate: Date?) {
    self.podcast = podcast
    self.episodeCount = episodeCount
    self.mostRecentEpisodeDate = mostRecentEpisodeDate
  }

  // MARK: Query Builders

  static func all(
    _ filter: PodcastFilter = { $0 }
  ) -> QueryInterfaceRequest<PodcastWithEpisodeMetadata> {
    filter(Podcast.all())
      .annotated(with: [
        Podcast.episodes.count.forKey(PodcastMetadataCodingKeys.episodeCount),
        Podcast.episodes.max(\.pubDate).forKey(PodcastMetadataCodingKeys.mostRecentEpisodeDate),
      ])
      .asRequest(of: PodcastWithEpisodeMetadata.self)
  }
}

// MARK: - PodcastDisplayable Helpers

extension PodcastWithEpisodeMetadata where PodcastType: PodcastDisplayable {
  func getPodcast() -> Podcast? { DisplayedPodcast.getPodcast(podcast) }
  func getUnsavedPodcast() -> UnsavedPodcast? { DisplayedPodcast.getUnsavedPodcast(podcast) }
}

// MARK: - FetchableRecord

extension PodcastWithEpisodeMetadata: FetchableRecord where PodcastType: FetchableRecord {
  init(row: Row) throws {
    self.podcast = try PodcastType(row: row)
    self.episodeCount = row[PodcastMetadataCodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[PodcastMetadataCodingKeys.mostRecentEpisodeDate]
  }
}
