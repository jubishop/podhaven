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
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.UpNextView.main)

  // MARK: - State Management

  var editMode: EditMode = .inactive
  var isSelecting: Bool {
    get { editMode.isEditing }
    set { editMode = newValue ? .active : .inactive }
  }

  var episodeList = SelectableListUseCase<PodcastEpisode, Episode.ID>(idKeyPath: \.id)

  enum SortMethod: String, CaseIterable {
    case oldestFirst = "Oldest First"
    case newestFirst = "Newest First"
    case mostFinished = "Most Finished"

    var menuSymbolName: String {
      switch self {
      case .oldestFirst:
        return "calendar"
      case .newestFirst:
        return "calendar.badge.clock"
      case .mostFinished:
        return "checkmark.circle"
      }
    }

    var menuIconColor: Color {
      switch self {
      case .oldestFirst:
        return .teal
      case .newestFirst:
        return .indigo
      case .mostFinished:
        return .green
      }
    }

    var sortMethod: (PodcastEpisode, PodcastEpisode) -> Bool {
      switch self {
      case .oldestFirst:
        return { lhs, rhs in lhs.episode.pubDate < rhs.episode.pubDate }
      case .newestFirst:
        return { lhs, rhs in lhs.episode.pubDate > rhs.episode.pubDate }
      case .mostFinished:
        return { lhs, rhs in
          // Primary sort: most finished first (highest currentTime)
          if lhs.episode.currentTime.seconds != rhs.episode.currentTime.seconds {
            return lhs.episode.currentTime.seconds > rhs.episode.currentTime.seconds
          }
          // Secondary sort: oldest publication date first
          return lhs.episode.pubDate < rhs.episode.pubDate
        }
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  // MARK: - Initialization

  func execute() async {
    do {
      for try await podcastEpisodes in observatory.queuedPodcastEpisodes() {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")

        self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Derived State

  var totalQueueDuration: CMTime {
    episodeList.filteredEntries.reduce(CMTime.zero) { total, podcastEpisode in
      total + podcastEpisode.episode.duration
    }
  }

  // MARK: - ManagingEpisodes

  func queueEpisodeOnTop(_ episode: PodcastEpisode, swipeAction: Bool) {
    Self.log.debug("Custom queueing of episode to top using UpNextViewModel")

    // We have to remove the item first to avoid janky move animation with swipe action
    if swipeAction { episodeList.allEntries.remove(episode) }

    Task { [weak self] in
      guard let self else { return }

      try await queue.unshift(episode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: PodcastEpisode, swipeAction: Bool) {
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
