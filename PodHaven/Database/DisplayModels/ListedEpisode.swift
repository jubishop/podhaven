// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import GRDB

struct ListedEpisode:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  enum Source: Hashable, Sendable {
    case saved(ListablePodcastEpisode)
    case unsaved(UnsavedPodcastEpisode)

    var canonicalEpisode: any EpisodeListable {
      switch self {
      case .saved(let episode): return episode
      case .unsaved(let episode): return episode
      }
    }

    var episodeID: Episode.ID? { canonicalEpisode.episodeID }
    var feedURL: FeedURL { canonicalEpisode.feedURL }
    var mediaGUID: MediaGUID { canonicalEpisode.mediaGUID }
    var title: String { canonicalEpisode.title }
    var pubDate: Date { canonicalEpisode.pubDate }
    var duration: CMTime { canonicalEpisode.duration }
    var currentTime: CMTime { canonicalEpisode.currentTime }
    var queueOrder: Int? { canonicalEpisode.queueOrder }
    var cacheStatus: Episode.CacheStatus { canonicalEpisode.cacheStatus }
    var finishDate: Date? { canonicalEpisode.finishDate }
    var image: URL { canonicalEpisode.image }
    var podcastImage: URL { canonicalEpisode.podcastImage }
    var saveInCache: Bool { canonicalEpisode.saveInCache }
    var hasTranscript: Bool { canonicalEpisode.hasTranscript }
    var rating: EpisodeRating? { canonicalEpisode.rating }
    var hasEmbedding: Bool { canonicalEpisode.hasEmbedding }

    // Header fields beyond `EpisodeListable`. The .saved arm has no list-row
    // source for `description` — surface the same nil placeholder the detail
    // view already showed pre-hydration; both arms carry `podcastTitle`.
    var podcastTitle: String {
      switch self {
      case .saved(let episode): return episode.podcastTitle
      case .unsaved(let episode): return episode.podcastTitle
      }
    }

    var description: String? {
      switch self {
      case .saved: return nil
      case .unsaved(let episode): return episode.description
      }
    }

    var queueDate: Date? {
      switch self {
      case .saved(let episode): return episode.queueDate
      case .unsaved(let episode): return episode.queueDate
      }
    }
    var creationDate: Date? {
      switch self {
      case .saved(let episode): return episode.creationDate
      case .unsaved: return nil
      }
    }

    var tagIDs: Set<Tag.ID>? {
      switch self {
      case .saved(let episode): return episode.tagIDs
      case .unsaved: return nil
      }
    }

    var searchableString: String {
      switch self {
      case .saved(let episode): return episode.searchableString
      case .unsaved(let episode): return episode.searchableString
      }
    }

    var unsaved: UnsavedPodcastEpisode? {
      guard case .unsaved(let episode) = self else { return nil }
      return episode
    }
  }

  let source: Source

  init(_ episode: ListablePodcastEpisode) { source = .saved(episode) }
  init(_ episode: UnsavedPodcastEpisode) { source = .unsaved(episode) }

  // MARK: - Identifiable

  var id: MediaGUID { mediaGUID }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) { hasher.combine(source) }
  static func == (lhs: ListedEpisode, rhs: ListedEpisode) -> Bool { lhs.source == rhs.source }

  // MARK: - EpisodeListable

  var episodeID: Episode.ID? { source.episodeID }
  var feedURL: FeedURL { source.feedURL }
  var mediaGUID: MediaGUID { source.mediaGUID }
  var title: String { source.title }
  var pubDate: Date { source.pubDate }
  var duration: CMTime { source.duration }
  var currentTime: CMTime { source.currentTime }
  var queueOrder: Int? { source.queueOrder }
  var cacheStatus: Episode.CacheStatus { source.cacheStatus }
  var finishDate: Date? { source.finishDate }
  var image: URL { source.image }
  var podcastImage: URL { source.podcastImage }
  var saveInCache: Bool { source.saveInCache }
  var hasTranscript: Bool { source.hasTranscript }
  var rating: EpisodeRating? { source.rating }
  var tagIDs: Set<Tag.ID>? { source.tagIDs }
  var creationDate: Date? { source.creationDate }
  var hasEmbedding: Bool { source.hasEmbedding }

  // MARK: - EpisodeDisplayable

  var podcastTitle: String { source.podcastTitle }
  var description: String? { source.description }
  var queueDate: Date? { source.queueDate }

  // MARK: - Searchable

  var searchableString: String { source.searchableString }

  // MARK: - Helpers

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    switch source {
    case .saved(let episode): return try await episode.getPodcastEpisode()
    case .unsaved(let episode): return try await episode.getOrCreatePodcastEpisodeSavingSeries()
    }
  }

  var unsaved: UnsavedPodcastEpisode? { source.unsaved }
}
