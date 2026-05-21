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
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

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

  enum LoadingState: Equatable {
    case loadingEpisodes
    case computingRecommendations
    case loaded
    case failed
  }

  private static let displayLimit = 100
  let title: String
  let filter: SQLExpression
  private(set) var loadingState: LoadingState = .loadingEpisodes

  // Keys the single `.task(id:)` block in the view. A sort or filterText
  // change restarts the observation; recommendation scoring runs only while
  // the recommendationScore sort is the one keyed here.
  @ObservationIgnored private var lastDisplayObservationKey: DisplayObservationKey?
  struct DisplayObservationKey: Hashable {
    let sort: SortMethod
    let filterText: String
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

    if currentSortMethod == .recommendationScore {
      await runRecommendationObservation()
    } else {
      await runStandardSortObservation()
    }
  }

  // Recommendation scoring runs only on demand — while the recommendationScore
  // sort is the selected one. Two producers feed the scoring pass: the
  // candidate set and the engine's scoring revision.
  private func runRecommendationObservation() async {
    // Hydrate straight from a score retained across an earlier selection so
    // toggling back to rec sort doesn't re-flash "Computing recommendations…".
    kickRecommendationHydration()

    await withTaskGroup(of: Void.self) { group in
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeCandidateSet()
      }
      group.addTask { [weak self] in
        guard let self else { return }
        await self.observeScoringRevision()
      }
    }
  }

  private func observeCandidateSet() async {
    do {
      let observation: AsyncValueObservation<[CandidateEpisode]> =
        observatory.embeddedCandidateEpisodes(filter: filter && textSearchFilter)
      for try await candidates in observation {
        try Task.checkCancellation()

        lastObservedCandidates = candidates
        restartRecommendationScoring(candidates: candidates)
        kickRecommendationHydration()
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "observeCandidateSet: observation failed for episode list '\(title)'",
        error
      )
      handleRecommendationFailure()
    }
  }

  private func observeScoringRevision() async {
    // Drop the first emission — $scoringRevision replays its current value on
    // subscribe, and the candidate observation already kicks the initial pass.
    for await _ in recommendationEngine.$scoringRevision.stream().dropFirst() {
      guard !Task.isCancelled else { return }
      restartRecommendationScoring(candidates: lastObservedCandidates)
    }
  }

  private func runStandardSortObservation() async {
    cancelRecommendationWork()

    do {
      let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
        observatory.listablePodcastEpisodes(
          filter: filter && currentSortMethod.sqlFilter && textSearchFilter,
          order: currentSortMethod.sqlOrdering,
          limit: Self.displayLimit
        )
      for try await podcastEpisodes in observation {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")
        transitionToLoaded(podcastEpisodes)
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "runStandardSortObservation: observation failed for episode list '\(title)'",
        error
      )
      handleLoadingFailure()
    }
  }

  private func pendingLoadingState() -> LoadingState {
    guard currentSortMethod == .recommendationScore else { return .loadingEpisodes }
    switch recommendationScoresState {
    case .pending: return .computingRecommendations
    case .failed: return .failed
    case .loaded: return .loadingEpisodes
    }
  }

  private func transitionToLoaded(_ episodes: [ListablePodcastEpisode]) {
    episodeList.allEntries = IdentifiedArray(uniqueElements: episodes)
    loadingState = .loaded
  }

  private func handleLoadingFailure() {
    guard !Task.isCancelled else { return }
    alert("Couldn't load episodes.")
    loadingState = .failed
  }

  // MARK: - Recommendation Hydration

  @ObservationIgnored private var lastObservedCandidates: [CandidateEpisode]?
  @ObservationIgnored private var recommendationHydrationTask: Task<Void, Never>?
  @ObservationIgnored private var hydratedScoreIDs: [Episode.ID] = []

  private func kickRecommendationHydration() {
    guard currentSortMethod == .recommendationScore else { return }
    switch recommendationScoresState {
    case .pending:
      return
    case .failed:
      loadingState = .failed
    case .loaded:
      startRecommendationHydration(for: topEpisodeIDsByScore())
    }
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
      transitionToLoaded([])
      return
    }

    recommendationHydrationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      do {
        let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
          self.observatory.listablePodcastEpisodes(
            filter: topIDs.contains(Episode.Columns.id),
            limit: Self.displayLimit
          )
        for try await listables in observation {
          try Task.checkCancellation()
          let byID = Dictionary(uniqueKeysWithValues: listables.map { ($0.id, $0) })
          var ordered = [ListablePodcastEpisode](capacity: topIDs.count)
          for id in topIDs {
            guard let listable = byID[id] else { continue }
            ordered.append(listable)
          }
          self.transitionToLoaded(ordered)
        }
      } catch is CancellationError {
      } catch {
        Self.log.caughtError(
          "startRecommendationHydration: observation failed for \(topIDs.count) ids",
          error
        )
        self.handleLoadingFailure()
      }
    }
  }

  // MARK: - Recommendations

  private enum RecommendationScoresState {
    case pending
    case failed
    case loaded([Episode.ID: Float])
  }

  private struct ScoredInputsKey: Equatable {
    let candidates: [CandidateEpisode]
    let scoringRevision: Int
  }

  @ObservationIgnored private var recommendationScoresState: RecommendationScoresState = .pending
  @ObservationIgnored private var lastScoredKey: ScoredInputsKey?
  @ObservationIgnored private var recommendationScoringTask: Task<Void, Never>?

  // Cancel-and-restart: any in-flight pass is cancelled so the latest inputs
  // win and a superseded pass never publishes stale rows.
  private func restartRecommendationScoring(candidates observedCandidates: [CandidateEpisode]?) {
    guard let candidates = observedCandidates else { return }

    let key = ScoredInputsKey(
      candidates: candidates,
      scoringRevision: recommendationEngine.scoringRevision
    )
    guard key != lastScoredKey else { return }

    recommendationScoringTask?.cancel()
    recommendationScoringTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      guard !Task.isCancelled else { return }

      let values: [Episode.ID: Float]
      if candidates.isEmpty {
        values = [:]
      } else {
        do {
          values = try await self.recommendationEngine.recommendationScores(for: candidates)
        } catch is CancellationError {
          return
        } catch {
          Self.log.caughtError(
            "restartRecommendationScoring: scoring failed",
            error
          )
          self.handleRecommendationFailure()
          return
        }
      }

      guard !Task.isCancelled else { return }

      self.recommendationScoresState = .loaded(values)
      self.lastScoredKey = key
      Self.log.debug(
        "Recommendation scoring landed \(values.count) scores for \(candidates.count) candidates"
      )
      self.kickRecommendationHydration()
    }
  }

  private func handleRecommendationFailure() {
    guard !Task.isCancelled else { return }
    recommendationScoresState = .failed
    lastScoredKey = nil
    guard currentSortMethod == .recommendationScore else { return }
    alert("Couldn't compute recommendations.")
    loadingState = .failed
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
    cancelRecommendationWork()
  }

  // `lastScoredKey` deliberately survives this teardown (see
  // `cancelRecommendationScoring`) so re-selecting the rec sort is instant.
  private func cancelRecommendationWork() {
    cancelRecommendationScoring()
    cancelRecommendationHydration()
  }

  private func cancelRecommendationScoring() {
    recommendationScoringTask?.cancel()
    recommendationScoringTask = nil
    lastObservedCandidates = nil
    // lastScoredKey is deliberately kept so a completed score survives a tab switch.
  }

  private func cancelRecommendationHydration() {
    recommendationHydrationTask?.cancel()
    recommendationHydrationTask = nil
    hydratedScoreIDs = []
  }
}
