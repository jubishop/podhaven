// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB

@dynamicMemberLookup
struct ListedEpisode:
  EpisodeListable,
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
    if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      hasher.combine(unsavedPodcastEpisode)
    } else if let listableEpisode = getListablePodcastEpisode() {
      hasher.combine(listableEpisode)
    } else {
      Assert.fatal("Can't make hash from: \(type(of: episode))")
    }
  }

  static func == (lhs: ListedEpisode, rhs: ListedEpisode) -> Bool {
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

    return false  // Different concrete types are not equal
  }

  // MARK: - EpisodeListable

  var mediaGUID: MediaGUID { episode.mediaGUID }
  var title: String { episode.title }
  var pubDate: Date { episode.pubDate }
  var duration: CMTime { episode.duration }
  var currentTime: CMTime { episode.currentTime }
  var queueOrder: Int? { episode.queueOrder }
  var cacheStatus: Episode.CacheStatus { episode.cacheStatus }
  var finishDate: Date? { episode.finishDate }
  var image: URL { episode.image }
  var podcastImage: URL { episode.podcastImage }
  var saveInCache: Bool { episode.saveInCache }

  // MARK: - Getters

  func getListablePodcastEpisode() -> ListablePodcastEpisode? {
    episode as? ListablePodcastEpisode
  }
  func getUnsavedPodcastEpisode() -> UnsavedPodcastEpisode? {
    episode as? UnsavedPodcastEpisode
  }

  func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let unsavedPodcastEpisode = getUnsavedPodcastEpisode() {
      return try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    } else if let listablePodcastEpisode = getListablePodcastEpisode() {
      return try await listablePodcastEpisode.getPodcastEpisode()
    }
    Assert.fatal("Can't make PodcastEpisode from: \(type(of: episode))")
  }
}
