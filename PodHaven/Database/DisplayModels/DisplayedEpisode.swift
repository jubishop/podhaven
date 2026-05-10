// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation

struct DisplayedEpisode:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  enum Source: Hashable, Sendable {
    case saved(PodcastEpisode)
    case unsaved(UnsavedPodcastEpisode)
    case initialPresentation(EpisodeDetailInitialEpisode)

    var canonicalEpisode: any EpisodeDisplayable {
      switch self {
      case .saved(let episode): return episode
      case .unsaved(let episode): return episode
      case .initialPresentation(let episode): return episode
      }
    }

    var saved: PodcastEpisode? {
      guard case .saved(let episode) = self else { return nil }
      return episode
    }

    var unsaved: UnsavedPodcastEpisode? {
      guard case .unsaved(let episode) = self else { return nil }
      return episode
    }
  }

  @DynamicInjected(\.repo) private var repo

  let source: Source

  init(_ episode: PodcastEpisode) { source = .saved(episode) }
  init(_ episode: UnsavedPodcastEpisode) { source = .unsaved(episode) }
  init(_ episode: EpisodeDetailInitialEpisode) { source = .initialPresentation(episode) }

  // MARK: - Identifiable

  var id: MediaGUID { mediaGUID }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) { hasher.combine(source) }
  static func == (lhs: DisplayedEpisode, rhs: DisplayedEpisode) -> Bool {
    lhs.source == rhs.source
  }

  // MARK: - EpisodeListable

  var feedURL: FeedURL { source.canonicalEpisode.feedURL }
  var image: URL { source.canonicalEpisode.image }
  var podcastImage: URL { source.canonicalEpisode.podcastImage }
  var saveInCache: Bool { source.canonicalEpisode.saveInCache }

  // MARK: - EpisodeFoundational

  var episodeID: Episode.ID? { source.canonicalEpisode.episodeID }
  var mediaGUID: MediaGUID { source.canonicalEpisode.mediaGUID }
  var title: String { source.canonicalEpisode.title }
  var pubDate: Date { source.canonicalEpisode.pubDate }
  var duration: CMTime { source.canonicalEpisode.duration }
  var currentTime: CMTime { source.canonicalEpisode.currentTime }
  var queueOrder: Int? { source.canonicalEpisode.queueOrder }
  var cacheStatus: Episode.CacheStatus { source.canonicalEpisode.cacheStatus }
  var finishDate: Date? { source.canonicalEpisode.finishDate }
  var rating: EpisodeRating? { source.canonicalEpisode.rating }

  // MARK: - EpisodeDisplayable

  var podcastTitle: String { source.canonicalEpisode.podcastTitle }
  var description: String? { source.canonicalEpisode.description }
  var queueDate: Date? { source.canonicalEpisode.queueDate }

  // MARK: - Helpers

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    switch source {
    case .saved(let podcastEpisode):
      return podcastEpisode
    case .unsaved(let unsavedPodcastEpisode):
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    case .initialPresentation:
      Assert.fatal("Cannot get-or-create from initial presentation: \(toString)")
    }
  }
}
