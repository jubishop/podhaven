// Copyright Justin Bishop, 2025

import Foundation
import GRDB

@dynamicMemberLookup
struct PodcastWithEpisodeMetadata<PodcastType: PodcastDisplayable>: Searchable, Stringable {
  // MARK: - Getters

  var isSaved: Bool { self.podcastID != nil }
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

  // MARK: - Getters

  func getPodcast() -> Podcast? { DisplayedPodcast.getPodcast(podcast) }
  func getUnsavedPodcast() -> UnsavedPodcast? { DisplayedPodcast.getUnsavedPodcast(podcast) }
}

extension PodcastWithEpisodeMetadata: FetchableRecord where PodcastType == Podcast {
  // MARK: - QueryInterfaceRequest

  static func all() -> QueryInterfaceRequest<PodcastWithEpisodeMetadata> {
    Podcast.all()
      .annotated(with: [
        Podcast.episodes.count.forKey(CodingKeys.episodeCount),
        Podcast.episodes.max(\.pubDate).forKey(CodingKeys.mostRecentEpisodeDate),
      ])
      .asRequest(of: PodcastWithEpisodeMetadata.self)
  }

  // MARK: - Custom Decoding

  enum CodingKeys: String, CodingKey, ColumnExpression {
    case episodeCount
    case mostRecentEpisodeDate
  }

  init(row: Row) throws {
    self.podcast = try Podcast(row: row)
    self.episodeCount = row[CodingKeys.episodeCount]
    self.mostRecentEpisodeDate = row[CodingKeys.mostRecentEpisodeDate]
  }
}
