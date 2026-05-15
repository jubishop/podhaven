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

  // Two observation keys feed two `.task(id:)` blocks in the view. The
  // candidate observation is filterText-only so it survives sort toggles —
  // the top-100 recommendations stay warm in the background regardless of
  // which sort the user is currently viewing.
  @ObservationIgnored private var lastDisplayObservationKey: DisplayObservationKey?
  struct CandidateObservationKey: Hashable {
    let filterText: String
  }
  struct DisplayObservationKey: Hashable {
    let sort: SortMethod
    let filterText: String
  }
  var candidateObservationKey: CandidateObservationKey {
    CandidateObservationKey(filterText: filterText)
  }
  var displayObservationKey: DisplayObservationKey {
    DisplayObservationKey(sort: currentSortMethod, filterText: filterText)
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

  // MARK: - Candidate Observation (always-on, background)

  // Runs whenever the view is visible, independent of the current sort
  // method. Maintains the top-100 recommendation IDs so that switching to
  // recommendation sort can hydrate immediately instead of waiting for a
  // cold scoring pass.
  func startCandidateObservation() async {
    startRecommendationContextObservation()
    startRecommendationAffinityObservation()

    do {
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
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "startCandidateObservation: observation failed for episode list '\(title)'",
        error
      )
      applyFailedScores()
    }
  }

  // MARK: - Display Observation

  func startDisplayObservation() async {
    let currentKey = displayObservationKey
    let keyChanged = lastDisplayObservationKey != nil && lastDisplayObservationKey != currentKey
    lastDisplayObservationKey = currentKey

    Self.log.debug(
      """
      Executing display observation for \(title) with key \(currentKey), changed: \(keyChanged)
      """
    )

    if keyChanged || episodeList.allEntries.isEmpty { loadingState = pendingLoadingState() }

    do {
      if currentSortMethod == .recommendationScore {
        // The candidate observation drives the rec-sort flow end-to-end;
        // this task only needs to (re)trigger hydration against whatever
        // top IDs are currently cached, then return. SwiftUI restarts this
        // body whenever sort or filterText changes.
        applyScoresIfRecSort()
      } else {
        try await runStandardSortObservation()
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "startDisplayObservation: observation failed for episode list '\(title)'",
        error
      )
    }
  }

  private func runStandardSortObservation() async throws {
    cancelRecommendationHydration()

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

  private func startRecommendationContextObservation() {
    if let recommendationContextObservationTask, !recommendationContextObservationTask.isCancelled {
      return
    }
    recommendationContextObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      // The first $contextRevision yield is Broadcast's on-subscribe
      // bootstrap. The candidate observation's first emission is what
      // kicks the initial fetch, so we drop the bootstrap here to avoid
      // double-fetching on view appear.
      var isBootstrap = true
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
