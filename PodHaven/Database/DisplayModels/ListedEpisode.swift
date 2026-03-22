// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation

@dynamicMemberLookup
struct ListedEpisode:
  EpisodeListable,
  Searchable,
  Hashable,
  Sendable
{
  @DynamicInjected(\.repo) private var repo

  let episode: any EpisodeListable

  init(_ episode: any EpisodeListable) {
    Assert.precondition(
      !(episode is ListedEpisode),
      "Cannot wrap an instance of itself as a ListedEpisode"
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
    } else if let listableEpisode = getListablePodcastEpisode() {
      hasher.combine(listableEpisode)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: episode))")
    }
  }

  static func == (lhs: ListedEpisode, rhs: ListedEpisode) -> Bool {
    if let leftPE = lhs.getPodcastEpisode(), let rightPE = rhs.getPodcastEpisode() {
      return leftPE == rightPE
    }
    if let leftUnsaved = lhs.getUnsavedPodcastEpisode(),
      let rightUnsaved = rhs.getUnsavedPodcastEpisode()
    {
      return leftUnsaved == rightUnsaved
    }
    if let leftListable = lhs.getListablePodcastEpisode(),
      let rightListable = rhs.getListablePodcastEpisode()
    {
      return leftListable == rightListable
    }
    return false
  }

  // MARK: - Stringable / Searchable

  var toString: String { episode.toString }
  var searchableString: String {
    if let searchable = episode as? any Searchable {
      return searchable.searchableString
    }
    return episode.title
  }

  // MARK: - EpisodeListable

  var episodeID: Episode.ID? { episode.episodeID }
  var mediaGUID: MediaGUID { episode.mediaGUID }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var currentTime: CMTime { episode.currentTime }
  var queueOrder: Int? { episode.queueOrder }
  var cacheStatus: Episode.CacheStatus { episode.cacheStatus }
  var saveInCache: Bool { episode.saveInCache }
  var finishDate: Date? { episode.finishDate }
  var image: URL { episode.image }
  var podcastImage: URL { episode.podcastImage }

  // MARK: - Getters

  func getListablePodcastEpisode() -> ListablePodcastEpisode? {
    episode as? ListablePodcastEpisode
  }
  func getUnsavedPodcastEpisode() -> UnsavedPodcastEpisode? {
    episode as? UnsavedPodcastEpisode
  }
  func getPodcastEpisode() -> PodcastEpisode? { episode as? PodcastEpisode }

  func getDisplayedEpisode() -> DisplayedEpisode? {
    guard let displayable = episode as? any EpisodeDisplayable else { return nil }
    return DisplayedEpisode(displayable)
  }

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = getPodcastEpisode() {
      return podcastEpisode
    } else if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else if let episodeID = episode.episodeID {
      guard let podcastEpisode = try await repo.podcastEpisode(episodeID) else {
        Assert.fatal("PodcastEpisode not found for saved episode \(episodeID)")
      }
      return podcastEpisode
    } else {
      Assert.fatal("Can't get or create PodcastEpisode from: \(type(of: episode))")
    }
  }
}
