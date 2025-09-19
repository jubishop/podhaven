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
    if let podcastEpisode = getPodcastEpisode() {
      hasher.combine(podcastEpisode)
    } else if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      hasher.combine(unsavedPodcastEpisode)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: episode))")
    }
  }

  static func == (lhs: DisplayableEpisode, rhs: DisplayableEpisode) -> Bool {
    if let leftPodcastEpisode = lhs.getPodcastEpisode(),
      let rightPodcastEpisode = rhs.getPodcastEpisode()
    {
      return leftPodcastEpisode == rightPodcastEpisode
    }

    if let leftUnsavedPodcastEpisode = lhs.getUnsavedPodcastEpisode(),
      let rightUnsavedPodcastEpisode = rhs.getUnsavedPodcastEpisode()
    {
      return leftUnsavedPodcastEpisode == rightUnsavedPodcastEpisode
    }

    return false  // Different concrete types are not equal
  }

  // MARK: - Stringable / Searchable

  var toString: String { episode.toString }
  var searchableString: String { episode.searchableString }

  // MARK: - EpisodeDisplayable

  var episodeID: Episode.ID? { episode.episodeID }
  var mediaGUID: MediaGUID { episode.mediaGUID }
  var title: String { episode.title }
  var podcastTitle: String { episode.podcastTitle }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var image: URL { episode.image }
  var description: String? { episode.description }
  var queued: Bool { episode.queued }
  var queueOrder: Int? { episode.queueOrder }
  var cacheStatus: Episode.CacheStatus { episode.cacheStatus }
  var started: Bool { episode.started }
  var currentTime: CMTime { episode.currentTime }
  var finished: Bool { episode.finished }

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
    } else if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
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
