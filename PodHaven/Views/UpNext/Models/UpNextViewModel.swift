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
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.UpNextView.main)

  // MARK: - State Management

  var editMode: EditMode {
    get { episodeList.isSelecting ? .active : .inactive }
    set { episodeList.setSelecting(newValue.isEditing) }
  }

  var episodeList = PowerList<ListablePodcastEpisode>()
  private(set) var recommendedEpisodes: IdentifiedArrayOf<ListablePodcastEpisode> = []

  private var recommendedPoolOrder: [Episode.ID] = []
  private var hydratedRecommendedListables: [Episode.ID: ListablePodcastEpisode] = [:]

  // MARK: - SelectableList

  // Recommendations live outside the PowerList, so the default
  // `episodeList.selectedEntries` misses them. Union them in here.
  var selectedEntries: IdentifiedArrayOf<ListablePodcastEpisode> {
    var result = episodeList.selectedEntries
    for rec in recommendedEpisodes where episodeList.isSelected[rec.id] {
      result.append(rec)
    }
    return result
  }

  var anySelected: Bool {
    episodeList.anySelected || recommendedEpisodes.contains { episodeList.isSelected[$0.id] }
  }

  var anyNotSelected: Bool {
    episodeList.anyNotSelected || recommendedEpisodes.contains { !episodeList.isSelected[$0.id] }
  }

  func selectAllEntries() {
    episodeList.selectAllEntries()
    for recommendedEpisode in recommendedEpisodes {
      episodeList.isSelected[recommendedEpisode.id] = true
    }
  }

  func unselectAllEntries() {
    episodeList.unselectAllEntries()
    for recommendedEpisode in recommendedEpisodes {
      episodeList.isSelected[recommendedEpisode.id] = false
    }
  }

  // MARK: - SortableEpisodeList

  enum SortMethod: SortingMethod {
    case newestFirst
    case oldestFirst
    case recentlyAdded
    case mostRecentlyQueued
    case leastRecentlyQueued
    case recommendationScore

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .recentlyAdded:
        return .sortByRecentlyAdded
      case .mostRecentlyQueued:
        return .sortByMostRecentlyQueued
      case .leastRecentlyQueued:
        return .sortByLeastRecentlyQueued
      case .recommendationScore:
        return .sortByRecommendationScore
      }
    }

    // Nil for recommendationScore: scoring is async, so `sort(by:)` resolves
    // the order off the engine's score map rather than a synchronous comparator.
    var sortMethod: ((ListablePodcastEpisode, ListablePodcastEpisode) -> Bool)? {
      switch self {
      case .newestFirst:
        return { lhs, rhs in lhs.pubDate > rhs.pubDate }
      case .oldestFirst:
        return { lhs, rhs in lhs.pubDate < rhs.pubDate }
      case .recentlyAdded:
        return { lhs, rhs in lhs.creationDate > rhs.creationDate }
      case .mostRecentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.queueDate ?? lhs.creationDate
          let rhsDate = rhs.queueDate ?? rhs.creationDate
          return lhsDate > rhsDate
        }
      case .leastRecentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.queueDate ?? lhs.creationDate
          let rhsDate = rhs.queueDate ?? rhs.creationDate
          return lhsDate < rhsDate
        }
      case .recommendationScore:
        return nil
      }
    }
  }

  // recommendationScore is hidden until the engine's scoring cache is warm:
  // a cold cache scores everything 0, and unlike the other sort sites UpNext
  // persists the result, so offering it cold would scramble the saved queue.
  // Reading the engine's observable flag here keeps the menu reactive without
  // mirroring it into local state.
  var allSortMethods: [SortMethod] {
    SortMethod.allCases.filter {
      $0 != .recommendationScore || recommendationEngine.hasScoringContext
    }
  }

  // MARK: - Initialization

  func execute() async {
    Self.log.debug("executing UpNextViewModel")

    await withDiscardingTaskGroup { group in
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeQueue()
      }
      group.addTask(priority: taskPriority(.utility)) { [weak self] in
        guard let self else { return }
        await self.observeRecommendations()
      }
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeOnDeckForRecommendations()
      }
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeRecommendationLimit()
      }
    }
  }

  private func observeQueue() async {
    for await podcastEpisodes in sharedState.$queuedPodcastEpisodes.stream() {
      guard !Task.isCancelled else { return }
      Self.log.debug("Updating \(podcastEpisodes.count) observed queue episodes")

      self.episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
    }
  }

  // The engine publishes a ranked pool keyed to the current scoring context.
  // We hydrate display rows here, intersected with the candidate gate so an
  // episode that's been queued/rated/finished drops out the moment its row
  // changes — no engine rebuild required. The hydrated rows feed
  // `rebuildRecommendedEpisodes`, which also excludes the onDeck episode and
  // slices to the user's N setting.
  private func observeRecommendations() async {
    var hydrationTask: Task<Void, Never>?
    defer { hydrationTask?.cancel() }

    for await ranking in sharedState.$recommendedEpisodePool.stream() {
      guard !Task.isCancelled else { return }
      Self.log.debug("Updating \(ranking.count) pool entries")

      hydrationTask?.cancel()
      recommendedPoolOrder = ranking
      let idSet = Set(ranking)
      hydratedRecommendedListables = hydratedRecommendedListables.filter {
        idSet.contains($0.key)
      }

      guard !ranking.isEmpty else {
        hydrationTask = nil
        rebuildRecommendedEpisodes()
        continue
      }

      hydrationTask = Task(priority: taskPriority(.utility)) { @MainActor [weak self] in
        guard let self else { return }
        do {
          let observation = self.observatory.listablePodcastEpisodes(
            filter: idSet.contains(Episode.Columns.id) && Episode.candidate
          )
          for try await listables in observation {
            guard !Task.isCancelled else { return }
            self.hydratedRecommendedListables = Dictionary(
              uniqueKeysWithValues: listables.map { ($0.id, $0) }
            )
            self.rebuildRecommendedEpisodes()
          }
        } catch {
          Self.log.caughtError(
            "observeRecommendations: hydration observation failed for \(idSet.count) ids",
            error
          )
        }
      }
    }
  }

  private func observeOnDeckForRecommendations() async {
    for await _ in sharedState.$currentEpisodeID.stream() {
      guard !Task.isCancelled else { return }
      rebuildRecommendedEpisodes()
    }
  }

  private func observeRecommendationLimit() async {
    for await _ in userSettings.$maxRecommendedEpisodesInUpNext.stream() {
      guard !Task.isCancelled else { return }
      rebuildRecommendedEpisodes()
    }
  }

  private func rebuildRecommendedEpisodes() {
    let limit = userSettings.maxRecommendedEpisodesInUpNext
    let currentEpisodeID = sharedState.currentEpisodeID
    var ordered: [ListablePodcastEpisode] = []
    ordered.reserveCapacity(min(limit, recommendedPoolOrder.count))
    for id in recommendedPoolOrder {
      if ordered.count >= limit { break }
      if id == currentEpisodeID { continue }
      guard let listable = hydratedRecommendedListables[id] else { continue }
      ordered.append(listable)
    }
    recommendedEpisodes = IdentifiedArray(uniqueElements: ordered)
  }

  // MARK: - Derived State

  var totalQueueTime: CMTime {
    episodeList.allEntries.reduce(CMTime.zero) { total, podcastEpisode in
      userSettings.showTimeRemainingInEpisodeLists
        ? total + (podcastEpisode.duration.safe - podcastEpisode.currentTime.safe)
        : total + podcastEpisode.duration.safe
    }
  }

  // MARK: - ManagingEpisodes

  func queueEpisodeOnTop(_ episode: ListablePodcastEpisode, swipeAction: Bool) {
    guard episode.queueOrder != 0 else { return }

    Self.log.debug("Custom queueing of episode to top using UpNextViewModel")

    // We have to remove the item first to avoid janky move animation with swipe action
    if swipeAction { episodeList.allEntries.remove(episode) }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.unshift(episode.id)
      } catch {
        Self.log.caughtError("queueEpisodeOnTop: failed for \(episode.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func queueEpisodeAtBottom(_ episode: ListablePodcastEpisode, swipeAction: Bool) {
    guard !isEpisodeAtBottomOfQueue(episode) else { return }

    Self.log.debug("Custom queueing of episode to bottom using UpNextViewModel")

    // We have to remove the item first to avoid janky move animation with swipe action
    if swipeAction { episodeList.allEntries.remove(episode) }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.append(episode.id)
      } catch {
        Self.log.caughtError("queueEpisodeAtBottom: failed for \(episode.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - SwiftUI List Functions

  func moveEpisode(from: IndexSet, to: Int) {
    guard from.count == 1, let from = from.first
    else { Assert.fatal("Somehow dragged none or several?") }

    Task { [weak self] in
      guard let self else { return }
      do {
        try await queue.insert(episodeList.allEntries[from].id, at: to)
      } catch {
        Self.log.caughtError("moveEpisode: failed to move from \(from) to \(to)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func refreshQueue() {
    let uncachedEpisodes = episodeList.allEntries.filter { podcastEpisode in
      podcastEpisode.cacheStatus != .cached
    }
    guard !uncachedEpisodes.isEmpty else { return }
    Self.log.debug("refreshQueue: caching \(uncachedEpisodes.count) uncached episodes")

    Self.log.debug(
      """
      Uncached episodes:
        \(uncachedEpisodes.map(\.toString).joined(separator: "\n  "))
      """
    )

    for podcastEpisode in uncachedEpisodes {
      Task(priority: taskPriority(.utility)) { [weak self] in
        guard let self else { return }
        do {
          try await cacheManager.downloadToCache(for: podcastEpisode.id)
        } catch {
          Self.log.caughtError(
            "refreshQueue: failed to cache \(podcastEpisode.toString)",
            error
          )
        }
      }
    }
  }

  // MARK: - Full List Actions

  func sort(by method: SortMethod) {
    Task { [weak self] in
      guard let self else { return }
      do {
        let entries = episodeList.allEntries
        let orderedIDs: [Episode.ID]
        if let comparator = method.sortMethod {
          orderedIDs = entries.sorted(by: comparator).map(\.id)
        } else {
          let scores = try await recommendationEngine.recommendationScores(
            forEpisodeIDs: entries.map(\.id)
          )
          // No scores (cold cache, or no queued row is embedded yet): leave the
          // persisted queue untouched rather than reorder it by tiebreakers.
          guard !scores.isEmpty else { return }
          orderedIDs =
            entries
            .sorted { lhs, rhs in
              let lhsScore = scores[lhs.id] ?? 0
              let rhsScore = scores[rhs.id] ?? 0
              if lhsScore != rhsScore { return lhsScore > rhsScore }
              if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
              return lhs.id > rhs.id
            }
            .map(\.id)
        }
        try await queue.updateQueueOrders(orderedIDs)
      } catch {
        Self.log.caughtError("sort: failed to sort queue by \(method)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
