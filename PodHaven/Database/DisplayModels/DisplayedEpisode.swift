// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct DisplayedEpisode:
  EpisodeDisplayable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let episode: any EpisodeListable

  init(_ episode: any EpisodeListable) {
    Assert.precondition(
      !(episode is DisplayedEpisode) && !(episode is ListedEpisode),
      "Cannot wrap a wrapper type as a DisplayedEpisode"
    )
    self.episode = episode
  }

  subscript<T>(dynamicMember keyPath: KeyPath<any EpisodeListable, T>) -> T {
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
    } else if let listablePodcastEpisode = getListablePodcastEpisode() {
      hasher.combine(listablePodcastEpisode)
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

    if let leftListable = lhs.getListablePodcastEpisode(),
      let rightListable = rhs.getListablePodcastEpisode()
    {
      return leftListable == rightListable
    }

    return false  // Different concrete types are not equal
  }

  // MARK: - EpisodeListable

  var image: URL { episode.image }
  var podcastImage: URL { episode.podcastImage }
  var saveInCache: Bool { episode.saveInCache }

  // MARK: - EpisodeFoundational

  var episodeID: Episode.ID? { episode.episodeID }
  var mediaGUID: MediaGUID { episode.mediaGUID }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var currentTime: CMTime { episode.currentTime }
  var queueOrder: Int? { episode.queueOrder }
  var cacheStatus: Episode.CacheStatus { episode.cacheStatus }
  var finishDate: Date? { episode.finishDate }

  // MARK: - EpisodeDisplayable (falls back to defaults for non-Displayable types)

  private var displayable: (any EpisodeDisplayable)? { episode as? any EpisodeDisplayable }

  var feedURL: FeedURL {
    if let displayable { return displayable.feedURL }
    Assert.fatal("feedURL not available on \(type(of: episode))")
  }
  var podcastTitle: String {
    if let displayable { return displayable.podcastTitle }
    if let listable = getListablePodcastEpisode() { return listable.podcastTitle }
    Assert.fatal("podcastTitle not available on \(type(of: episode))")
  }
  var description: String? { displayable?.description }
  var queueDate: Date? { displayable?.queueDate }

  // MARK: - Helpers

  static func getOrCreatePodcastEpisode(_ episode: any EpisodeListable) async throws
    -> PodcastEpisode
  {
    try await getDisplayedEpisode(episode).getOrCreatePodcastEpisode()
  }
  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = getPodcastEpisode() {
      return podcastEpisode
    } else if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else if let listablePodcastEpisode = getListablePodcastEpisode() {
      return try await listablePodcastEpisode.getPodcastEpisode()
    } else {
      Assert.fatal("Can't make PodcastEpisode from: \(type(of: episode))")
    }
  }

  static func getPodcastEpisode(_ episode: any EpisodeListable) -> PodcastEpisode? {
    getDisplayedEpisode(episode).getPodcastEpisode()
  }
  func getPodcastEpisode() -> PodcastEpisode? { episode as? PodcastEpisode }

  static func getUnsavedPodcastEpisode(_ episode: any EpisodeListable) -> UnsavedPodcastEpisode? {
    getDisplayedEpisode(episode).getUnsavedPodcastEpisode()
  }
  func getUnsavedPodcastEpisode() -> UnsavedPodcastEpisode? { episode as? UnsavedPodcastEpisode }
  func getListablePodcastEpisode() -> ListablePodcastEpisode? {
    episode as? ListablePodcastEpisode
  }

  static func toOriginalUnsavedPodcastEpisode(_ episode: any EpisodeListable) throws
    -> UnsavedPodcastEpisode
  {
    try getDisplayedEpisode(episode).toOriginalUnsavedPodcastEpisode()
  }
  func toOriginalUnsavedPodcastEpisode() throws -> UnsavedPodcastEpisode {
    if let podcastEpisode = getPodcastEpisode() {
      return try podcastEpisode.toOriginalUnsavedPodcastEpisode()
    } else if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      return try unsavedPodcastEpisode.toOriginalUnsavedPodcastEpisode()
    } else {
      Assert.fatal("Can't make Original UnsavedPodcastEpisode from: \(type(of: episode))")
    }
  }

  static func getDisplayedEpisode(_ episode: any EpisodeListable) -> DisplayedEpisode {
    guard let displayedEpisode = episode as? DisplayedEpisode
    else { return DisplayedEpisode(episode) }

    return displayedEpisode
  }
}
