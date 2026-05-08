// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB

struct ListedEpisode:
  EpisodeListable,
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
    var rating: EpisodeRating? { canonicalEpisode.rating }
    var tagIDs: Set<Tag.ID>? { canonicalEpisode.tagIDs }

    var unsavedPodcastEpisode: UnsavedPodcastEpisode? {
      guard case .unsaved(let episode) = self else { return nil }
      return episode
    }
  }

  @DynamicInjected(\.repo) private var repo

  let source: Source

  init(_ episode: ListablePodcastEpisode) { source = .saved(episode) }
  init(_ episode: UnsavedPodcastEpisode) { source = .unsaved(episode) }

  // MARK: - Identifiable

  var id: MediaGUID { mediaGUID }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) { hasher.combine(source) }
  static func == (lhs: ListedEpisode, rhs: ListedEpisode) -> Bool { lhs.source == rhs.source }

  // MARK: - EpisodeListable

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
  var rating: EpisodeRating? { source.rating }
  var tagIDs: Set<Tag.ID>? { source.tagIDs }

  // MARK: - Helpers

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    switch source {
    case .saved(let episode): return try await episode.getPodcastEpisode()
    case .unsaved(let episode): return try await repo.upsertPodcastEpisode(episode)
    }
  }

  var unsavedPodcastEpisode: UnsavedPodcastEpisode? { source.unsavedPodcastEpisode }
}
