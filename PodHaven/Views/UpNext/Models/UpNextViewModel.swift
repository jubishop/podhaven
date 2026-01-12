// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor class UpNextViewModel: ManagingEpisodes, SelectableEpisodeList {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.UpNextView.main)

  // MARK: - State Management

  var editMode: EditMode {
    get { episodeList.isSelecting ? .active : .inactive }
    set { episodeList.setSelecting(newValue.isEditing) }
  }

  var episodeList = PowerList<PodcastEpisode>()

  enum SortMethod: SortingMethod {
    case newestFirst
    case oldestFirst
    case mostRecentlyQueued
    case leastRecentlyQueued

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .mostRecentlyQueued:
        return .sortByMostRecentlyQueued
      case .leastRecentlyQueued:
        return .sortByLeastRecentlyQueued
      }
    }

    var sortMethod: (PodcastEpisode, PodcastEpisode) -> Bool {
      switch self {
      case .newestFirst:
        return { lhs, rhs in lhs.episode.pubDate > rhs.episode.pubDate }
      case .oldestFirst:
        return { lhs, rhs in lhs.episode.pubDate < rhs.episode.pubDate }
      case .mostRecentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.episode.queueDate ?? lhs.episode.creationDate
          let rhsDate = rhs.episode.queueDate ?? rhs.episode.creationDate
          return lhsDate > rhsDate
        }
      case .leastRecentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.episode.queueDate ?? lhs.episode.creationDate
          let rhsDate = rhs.episode.queueDate ?? rhs.episode.creationDate
          return lhsDate < rhsDate
        }
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  // MARK: - Initialization

  func execute() async {
    Self.log.debug("executing UpNextViewModel")

    for await podcastEpisodes in sharedState.queuedPodcastEpisodesStream() {
      guard !Task.isCancelled else { return }
      Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")

      self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
    }
  }

  // MARK: - Derived State

  var totalQueueDuration: CMTime {
    episodeList.filteredEntries.reduce(CMTime.zero) { total, podcastEpisode in
      total + (podcastEpisode.episode.duration.safe - podcastEpisode.episode.currentTime.safe)
    }
  }

  // MARK: - ManagingEpisodes

  func queueEpisodeOnTop(_ episode: PodcastEpisode, swipeAction: Bool) {
    guard episode.queueOrder != 0 else { return }

    Self.log.debug("Custom queueing of episode to top using UpNextViewModel")

    // We have to remove the item first to avoid janky move animation with swipe action
    if swipeAction { episodeList.allEntries.remove(episode) }

    Task { [weak self] in
      guard let self else { return }

      try await queue.unshift(episode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: PodcastEpisode, swipeAction: Bool) {
    guard !isEpisodeAtBottomOfQueue(episode) else { return }

    Self.log.debug("Custom queueing of episode to bottom using UpNextViewModel")

    // We have to remove the item first to avoid janky move animation with swipe action
    if swipeAction { episodeList.allEntries.remove(episode) }

    Task { [weak self] in
      guard let self else { return }

      try await queue.append(episode.id)
    }
  }

  // MARK: - SwiftUI List Functions

  func moveEpisode(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Assert.fatal("Somehow dragged none or several?") }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.insert(episodeList.filteredEntries[from].episode.id, at: to)
      } catch {
        Self.log.error(error)
      }
    }
  }

  func refreshQueue() {
    Self.log.debug("refreshQueue: downloading and caching uncached episodes")

    let uncachedEpisodes = episodeList.filteredEntries.filter { podcastEpisode in
      podcastEpisode.episode.cacheStatus != .cached
    }
    guard !uncachedEpisodes.isEmpty else { return }

    Self.log.debug(
      """
      Uncached episodes:
        \(uncachedEpisodes.map(\.toString).joined(separator: "\n  "))
      """
    )

    for podcastEpisode in uncachedEpisodes {
      Task { [weak self] in
        guard let self else { return }
        do {
          try await cacheManager.downloadToCache(for: podcastEpisode.id)
        } catch {
          Self.log.error(error)
        }
      }
    }
  }

  // MARK: - Full List Actions

  func sort(by method: SortMethod) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let sortedEpisodes = episodeList.filteredEntries.sorted(by: method.sortMethod)
        try await queue.updateQueueOrders(sortedEpisodes.map(\.episode.id))
      } catch {
        Self.log.error(error)
      }
    }
  }

  // MARK: - Selected Item Actions

  func removeSelectedFromQueue() {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.dequeue(episodeList.selectedEntryIDs)
      } catch {
        Self.log.error(error)
      }
    }
  }
}
