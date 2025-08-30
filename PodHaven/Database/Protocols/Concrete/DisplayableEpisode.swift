// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayableEpisode:
  EpisodeDisplayable,
  EpisodeFilterable,
  Identifiable,
  Searchable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let episode: any EpisodeDisplayable & EpisodeFilterable

  subscript<T>(dynamicMember keyPath: KeyPath<any EpisodeDisplayable, T>) -> T {
    episode[keyPath: keyPath]
  }

  // MARK: - Identifiable

  var id: MediaGUID { mediaGUID }

  // MARK: - Hashable / Equatable

  func hash(into hasher: inout Hasher) {
    hasher.combine(episode.mediaGUID)
  }

  static func == (lhs: DisplayableEpisode, rhs: DisplayableEpisode) -> Bool {
    lhs.mediaGUID == rhs.mediaGUID
  }

  // MARK: - Searchable

  var searchableString: String { episode.searchableString }

  // MARK: - EpisodeDisplayable / EpisodeFilterable

  var mediaGUID: MediaGUID { episode.mediaGUID }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var image: URL { episode.image }
  var cached: Bool { episode.cached }
  var description: String? { episode.description }
  var podcastTitle: String { episode.podcastTitle }
  var started: Bool { episode.started }
  var completed: Bool { episode.completed }
  var queued: Bool { episode.queued }

  // MARK: - Helpers

  func toPodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = episode as? PodcastEpisode {
      return podcastEpisode
    } else if let unsavedPodcastEpisode = episode as? UnsavedPodcastEpisode {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else {
      Assert.fatal("Unsupported episode type: \(type(of: episode))")
    }
  }
}
