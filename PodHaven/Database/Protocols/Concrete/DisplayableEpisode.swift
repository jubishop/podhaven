// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayableEpisode:
  EpisodeDisplayable,
  Identifiable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let episode: any EpisodeDisplayable

  init(_ episode: any EpisodeDisplayable) {
    Assert.precondition(
      !(episode is DisplayableEpisode),
      "Cannot wrap an instance of itself as a DisplayableEpisode"
    )

    self.episode = episode
  }

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

  // MARK: - Stringable

  var toString: String { episode.toString }

  // MARK: - Searchable

  var searchableString: String { episode.searchableString }

  // MARK: - EpisodeDisplayable

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

  static func getOrCreatePodcastEpisode(_ episode: any EpisodeDisplayable) async throws
    -> PodcastEpisode
  {
    guard let displayableEpisode = episode as? DisplayableEpisode
    else { return try await DisplayableEpisode(episode).getOrCreatePodcastEpisode() }

    return try await displayableEpisode.getOrCreatePodcastEpisode()
  }

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = getPodcastEpisode() {
      return podcastEpisode
    } else if let unsavedPodcastEpisode = episode as? UnsavedPodcastEpisode {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else {
      Assert.fatal("Can't make PodcastEpisode from: \(type(of: episode))")
    }
  }

  func getPodcastEpisode() -> PodcastEpisode? {
    episode as? PodcastEpisode
  }

  func getUnsavedPodcastEpisode() -> UnsavedPodcastEpisode? {
    episode as? UnsavedPodcastEpisode
  }
}
