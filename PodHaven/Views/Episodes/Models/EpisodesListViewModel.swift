// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class EpisodesListViewModel:
  ManagingEpisodes,
  SelectableEpisodeList,
  SortableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.EpisodesView.list)

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<ListablePodcastEpisode>()

  enum SortMethod: String, Codable, DefaultsStorable, SortingMethod {
    case newestFirst
    case oldestFirst
    case recentlyAdded
    case longest
    case shortest
    case recentlyFinished
    case recentlyQueued
    case recommendationScore

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .recentlyAdded:
        return .sortByRecentlyAdded
      case .longest:
        return .sortByLongest
      case .shortest:
        return .sortByShortest
      case .recentlyFinished:
        return .sortByRecentlyFinished
      case .recentlyQueued:
        return .sortByMostRecentlyQueued
      case .recommendationScore:
        return .sortByRecommendationScore
      }
    }

    var sqlOrdering: SQLOrdering? {
      switch self {
      case .newestFirst:
        return Episode.Columns.pubDate.desc
      case .oldestFirst:
        return Episode.Columns.pubDate.asc
      case .recentlyAdded:
        return Episode.Columns.creationDate.desc
      case .longest:
        return Episode.Columns.duration.desc
      case .shortest:
        return Episode.Columns.duration.asc
      case .recentlyFinished:
        return (Episode.Columns.finishDate ?? Date.distantPast).desc
      case .recentlyQueued:
        return (Episode.Columns.queueDate ?? Date.distantPast).desc
      case .recommendationScore:
        // Sorted in memory from the cached score map.
        return nil
      }
    }

    var sqlFilter: SQLExpression {
      switch self {
      case .recentlyFinished:
        return Episode.finished
      case .recentlyQueued:
        return Episode.previouslyQueued
      default: return AppDB.NoOp
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  @ObservationIgnored @PersistedBroadcast var currentSortMethod: SortMethod

  // MARK: - Filter Text

  private var textSearchFilter: SQLExpression {
    filterText
      .split(separator: /\s+/)
      .map { word in
        let pattern = "%\(word.lowercased())%"
        return Episode.contains(pattern) || Podcast.contains(pattern)
      }
      .reduce(AppDB.NoOp) { $0 && $1 }
  }

  private var filterText = ""

  @ObservationIgnored lazy var filterDebouncer = StringDebouncer(
    debounceDuration: .milliseconds(400)
  ) { [weak self] filteredText in
    guard let self else { return }
    self.filterText = filteredText
  }

  // MARK: - State Management

  enum LoadingState {
    case loadingEpisodes
    case computingRecommendations
    case recommendationFailed
    case ready
  }

  private static let displayLimit = 100
  let title: String
  let filter: SQLExpression
  private(set) var loadingState: LoadingState = .loadingEpisodes

  @ObservationIgnored private var lastObservationKey: ObservationKey?
  struct ObservationKey: Hashable {
    let sort: SortMethod
    let filterText: String
  }
  var observationKey: ObservationKey {
    ObservationKey(sort: currentSortMethod, filterText: filterText)
  }

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    self._currentSortMethod = PersistedBroadcast(
      wrappedValue: SortMethod.newestFirst,
      "EpisodesList-sortMethod-\(title)"
    )
    self.title = title
    self.filter = filter
  }

  // MARK: - Observation

  func startObservation() async {
    let currentKey = observationKey
    let keyChanged = lastObservationKey != nil && lastObservationKey != currentKey
    lastObservationKey = currentKey

    Self.log.debug(
      """
      Executing observation for \(title) with key \(currentKey), changed: \(keyChanged)
      """
    )

    if keyChanged || episodeList.allEntries.isEmpty { loadingState = pendingLoadingState() }

    startRecommendationObservation()

    do {
      if currentSortMethod == .recommendationScore {
        try await runRecommendationSortObservation()
      } else {
        try await runStandardSortObservation()
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "startObservation: observation failed for episode list '\(title)'",
        error
      )
      if currentSortMethod == .recommendationScore { applyFailedScores() }
    }
  }

  private func runStandardSortObservation() async throws {
    cancelRecommendationHydration()
    lastObservedCandidates = nil

    let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
      observatory.listablePodcastEpisodes(
        filter: filter && currentSortMethod.sqlFilter && textSearchFilter,
        order: currentSortMethod.sqlOrdering,
        limit: Self.displayLimit
      )
    for try await podcastEpisodes in observation {
      try Task.checkCancellation()
      Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")
      episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
      loadingState = .ready
    }
  }

  private func runRecommendationSortObservation() async throws {
    let observation: AsyncValueObservation<[CandidateEpisode]> =
      observatory.embeddedCandidateEpisodes(filter: filter && textSearchFilter)
    for try await candidates in observation {
      try Task.checkCancellation()

      lastObservedCandidates = candidates
      if lastScoredCandidates != candidates {
        lastScoredCandidates = candidates
        kickRecommendationFetch(candidates: candidates)
      }

      applyScoresIfRecSort()
    }
  }

  private func pendingLoadingState() -> LoadingState {
    guard currentSortMethod == .recommendationScore else { return .loadingEpisodes }
    switch recommendationScoresState {
    case .pending: return .computingRecommendations
    case .failed: return .recommendationFailed
    case .loaded: return .loadingEpisodes
    }
  }

  // MARK: - Recommendation Scoring

  private enum RecommendationScoresState {
    case pending
    case failed
    case loaded([Episode.ID: Float])
  }

  @ObservationIgnored private var recommendationScoresState: RecommendationScoresState = .pending
  @ObservationIgnored private var lastObservedCandidates: [CandidateEpisode]?
  @ObservationIgnored private var lastScoredCandidates: [CandidateEpisode]?
  @ObservationIgnored private var recommendationContextObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationAffinityObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationFetchTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationHydrationTask: Task<Void, Never>?
  @ObservationIgnored private var hydratedScoreIDs: [Episode.ID] = []

  private func startRecommendationObservation() {
    startRecommendationContextObservation()
    startRecommendationAffinityObservation()
  }

  private func startRecommendationContextObservation() {
    if let recommendationContextObservationTask, !recommendationContextObservationTask.isCancelled {
      return
    }
    let skipInitialBootstrap = currentSortMethod == .recommendationScore
    recommendationContextObservationTask = Task(priority: taskPriority(.utility)) {
      [weak self, skipInitialBootstrap] in
      guard let self else { return }
      var isBootstrap = skipInitialBootstrap
      for await _ in self.recommendationEngine.$contextRevision.stream() {
        guard !Task.isCancelled else { return }
        if isBootstrap {
          isBootstrap = false
          continue
        }
        self.kickRecommendationFetch(candidates: self.lastObservedCandidates)
      }
    }
  }

  private func startRecommendationAffinityObservation() {
    if let recommendationAffinityObservationTask, !recommendationAffinityObservationTask.isCancelled
    {
      return
    }
    recommendationAffinityObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      for await _ in self.userSettings.$podcastAffinityWeight.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        self.kickRecommendationFetch(candidates: self.lastObservedCandidates)
      }
    }
  }

  private func kickRecommendationFetch(candidates: [CandidateEpisode]? = nil) {
    recommendationFetchTask?.cancel()
    recommendationFetchTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await self.fetchAndApplyRecommendationScores(observedCandidates: candidates)
    }
  }

  private func fetchAndApplyRecommendationScores(observedCandidates: [CandidateEpisode]?) async {
    let candidates: [CandidateEpisode]
    if let observedCandidates {
      candidates = observedCandidates
    } else {
      let baseFilter = filter && textSearchFilter
      do {
        candidates = try await recommendationRepo.embeddedCandidateEpisodes(filter: baseFilter)
      } catch is CancellationError {
        return
      } catch {
        Self.log.caughtError(
          "fetchAndApplyRecommendationScores: candidate fetch failed",
          error
        )
        applyFailedScores()
        return
      }
    }

    guard !Task.isCancelled else { return }

    let scoreMap: [Episode.ID: RecommendationScore]
    if candidates.isEmpty {
      scoreMap = [:]
    } else {
      do {
        scoreMap = try await recommendationEngine.recommendations(for: candidates)
      } catch is CancellationError {
        return
      } catch {
        Self.log.caughtError(
          "fetchAndApplyRecommendationScores: scoring failed",
          error
        )
        applyFailedScores()
        return
      }
    }

    guard !Task.isCancelled else { return }

    var values = [Episode.ID: Float](capacity: scoreMap.count)
    for (id, score) in scoreMap { values[id] = score.value }
    recommendationScoresState = .loaded(values)
    lastScoredCandidates = candidates
    Self.log.debug(
      "Recommendation scoring landed \(values.count) scores for \(candidates.count) candidates"
    )
    applyScoresIfRecSort()
  }

  private func applyFailedScores() {
    guard !Task.isCancelled else { return }
    recommendationScoresState = .failed
    guard currentSortMethod == .recommendationScore else { return }
    loadingState = .recommendationFailed
  }

  private func applyScoresIfRecSort() {
    guard currentSortMethod == .recommendationScore else { return }
    guard case .loaded = recommendationScoresState else { return }
    startRecommendationHydration(for: topEpisodeIDsByScore())
  }

  private func startRecommendationHydration(for topIDs: [Episode.ID]) {
    if hydratedScoreIDs == topIDs,
      let recommendationHydrationTask,
      !recommendationHydrationTask.isCancelled
    {
      return
    }

    recommendationHydrationTask?.cancel()
    hydratedScoreIDs = topIDs

    guard !topIDs.isEmpty else {
      recommendationHydrationTask = nil
      episodeList.allEntries = []
      loadingState = .ready
      return
    }

    let idSet = Set(topIDs)
    recommendationHydrationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      do {
        let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
          self.observatory.listablePodcastEpisodes(
            filter: idSet.contains(Episode.Columns.id),
            limit: Self.displayLimit
          )
        for try await listables in observation {
          try Task.checkCancellation()
          self.applyRecommendationHydration(listables, rankOrder: topIDs)
        }
      } catch is CancellationError {
      } catch {
        Self.log.caughtError(
          "startRecommendationHydration: observation failed for \(topIDs.count) ids",
          error
        )
      }
    }
  }

  private func applyRecommendationHydration(
    _ listables: [ListablePodcastEpisode],
    rankOrder: [Episode.ID]
  ) {
    let byID = Dictionary(uniqueKeysWithValues: listables.map { ($0.id, $0) })
    var ordered = [ListablePodcastEpisode](capacity: rankOrder.count)
    for id in rankOrder {
      guard let listable = byID[id] else { continue }
      ordered.append(listable)
    }
    episodeList.allEntries = IdentifiedArray(uniqueElements: ordered)
    loadingState = .ready
  }

  private func cancelRecommendationHydration() {
    recommendationHydrationTask?.cancel()
    recommendationHydrationTask = nil
    hydratedScoreIDs = []
  }

  private func topEpisodeIDsByScore() -> [Episode.ID] {
    guard case .loaded(let scores) = recommendationScoresState, !scores.isEmpty else { return [] }
    return
      scores
      .sorted { lhs, rhs in
        if lhs.value != rhs.value { return lhs.value > rhs.value }
        return lhs.key > rhs.key
      }
      .prefix(Self.displayLimit)
      .map(\.key)
  }

  // MARK: - Disappear

  func disappear() {
    recommendationContextObservationTask?.cancel()
    recommendationContextObservationTask = nil
    recommendationAffinityObservationTask?.cancel()
    recommendationAffinityObservationTask = nil
    recommendationFetchTask?.cancel()
    recommendationFetchTask = nil
    cancelRecommendationHydration()
    lastObservedCandidates = nil
    lastScoredCandidates = nil
  }
}
