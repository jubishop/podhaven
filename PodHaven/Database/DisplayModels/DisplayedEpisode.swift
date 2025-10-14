// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayedEpisode:
  EpisodeDisplayable,
  Searchable,
  Stringable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let episode: any EpisodeDisplayable

  init(_ episode: any EpisodeDisplayable) {
    Assert.precondition(
      !(episode is DisplayedEpisode),
      "Cannot wrap an instance of itself as a DisplayedEpisode"
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

  static func == (lhs: DisplayedEpisode, rhs: DisplayedEpisode) -> Bool {
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
    try await getDisplayedEpisode(episode).getOrCreatePodcastEpisode()
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

  static func getPodcastEpisode(_ episode: any EpisodeDisplayable) -> PodcastEpisode? {
    getDisplayedEpisode(episode).getPodcastEpisode()
  }
  func getPodcastEpisode() -> PodcastEpisode? { episode as? PodcastEpisode }

  static func getUnsavedPodcastEpisode(_ episode: any EpisodeDisplayable) -> UnsavedPodcastEpisode?
  {
    getDisplayedEpisode(episode).getUnsavedPodcastEpisode()
  }
  func getUnsavedPodcastEpisode() -> UnsavedPodcastEpisode? { episode as? UnsavedPodcastEpisode }

  private static func getDisplayedEpisode(_ episode: any EpisodeDisplayable) -> DisplayedEpisode {
    guard let displayedEpisode = episode as? DisplayedEpisode
    else { return DisplayedEpisode(episode) }

    return displayedEpisode
  }
}
