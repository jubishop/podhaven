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
  @ObservationIgnored @DynamicInjected(\.dateProvider) private var dateProvider
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.smartListRepo) private var smartListRepo
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  private static let log = Log.as(LogSubsystem.EpisodesView.list)

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<ListablePodcastEpisode>()

  // recommendationScore is hidden until the engine's scoring cache is warm:
  // a cold cache produces no scores, which collapses the rec sort to an empty
  // list. Reading the engine's observable flag keeps the menu reactive without
  // mirroring it into local state.
  var allSortMethods: [SmartListSortMethod] {
    SmartListSortMethod.allCases.filter {
      $0 != .recommendationScore || recommendationEngine.hasScoringContext
    }
  }

  // Write-through: the setter persists the pick onto the SmartList row and the
  // row observation reads it back, so the row stays the single source of truth.
  // No optimistic local write — the pick → DB write → observation tick → UI
  // round-trip is fast.
  var currentSortMethod: SmartListSortMethod {
    get { rowSortMethod }
    set { persistSortMethod(newValue) }
  }

  private var rowSortMethod: SmartListSortMethod

  private func persistSortMethod(_ sortMethod: SmartListSortMethod) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await smartListRepo.updateSortMethod(smartListID, to: sortMethod)
      } catch {
        Self.log.caughtError(
          "persistSortMethod: failed to persist \(sortMethod.rawValue) for '\(title)'",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Filter Text

  private var textSearchFilter: SQLExpression {
    Episode.matchesText(allWordsIn: filterText)
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
    case loading
    case loaded
    case failed
  }

  private static let displayLimit = 100
  let smartListID: SmartList.ID
  private(set) var title: String
  private(set) var smartListFilter: SmartListFilter
  private(set) var alwaysShowPodcastImage: Bool
  private(set) var loadingState: LoadingState = .loading

  // Compiled fresh at each observation (re)start so relative publish-date
  // cutoffs are fixed per observation, not per view-model lifetime.
  private var filter: SQLExpression {
    SmartListFilterEngine.sqlExpression(for: smartListFilter, referenceDate: dateProvider.now)
  }

  // Keys the single `.task(id:)` block in the view. A sort, filter, or
  // filterText change restarts the observation; recommendation scoring runs
  // only while the recommendationScore sort is the one keyed here. Keyed on the
  // SmartListFilter value, not the compiled expression — SQLExpression isn't
  // Hashable.
  @ObservationIgnored private var lastDisplayObservationKey: DisplayObservationKey?
  struct DisplayObservationKey: Hashable {
    let sort: SmartListSortMethod
    let filterText: String
    let filter: SmartListFilter
  }
  var displayObservationKey: DisplayObservationKey {
    DisplayObservationKey(sort: currentSortMethod, filterText: filterText, filter: smartListFilter)
  }

  // MARK: - Initialization

  init(smartList: SmartList) {
    self.smartListID = smartList.id
    self.title = smartList.title
    self.smartListFilter = smartList.filter
    self.alwaysShowPodcastImage = smartList.alwaysShowPodcastImage
    self.rowSortMethod = smartList.sortMethod
  }

  // MARK: - Smart List Row Observation

  // Long-lived while the view is on screen; keeps title, filter, and sort in
  // step with edits from the configurator sheet (or this view model's own sort
  // writes). A deleted row pops the Episodes tab back to the hub.
  func observeSmartList() async {
    do {
      let observation: AsyncValueObservation<SmartList?> = observatory.smartList(smartListID)
      for try await smartList in observation {
        try Task.checkCancellation()
        guard let smartList else {
          Self.log.debug("Smart List '\(title)' was deleted; popping to the hub")
          navigation.episodes.path = []
          return
        }
        if title != smartList.title { title = smartList.title }
        if smartListFilter != smartList.filter { smartListFilter = smartList.filter }
        if alwaysShowPodcastImage != smartList.alwaysShowPodcastImage {
          alwaysShowPodcastImage = smartList.alwaysShowPodcastImage
        }
        if rowSortMethod != smartList.sortMethod { rowSortMethod = smartList.sortMethod }
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError("observeSmartList: observation failed for '\(title)'", error)
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

    if keyChanged || episodeList.allEntries.isEmpty { loadingState = .loading }

    if currentSortMethod == .recommendationScore {
      await runRecommendationObservation()
    } else {
      await runStandardSortObservation()
    }
  }

  // Runs only while the recommendationScore sort is selected. The candidate
  // observation kicks a pass per candidate-set change; the coordinator owns the
  // `$scoringRevision` trigger.
  private func runRecommendationObservation() async {
    cancelRecommendationWork()
    recommendationCoordinator.startObservations()
    await observeCandidateSet()
  }

  private func observeCandidateSet() async {
    do {
      let observation: AsyncValueObservation<[CandidateEpisode]> =
        observatory.embeddedCandidateEpisodes(filter: filter && textSearchFilter)
      for try await candidates in observation {
        try Task.checkCancellation()

        lastObservedCandidates = candidates
        recommendationCoordinator.refresh()
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

  private func transitionToLoaded(_ episodes: [ListablePodcastEpisode]) {
    episodeList.allEntries = IdentifiedArray(uniqueElements: episodes)
    loadingState = .loaded
  }

  private func handleLoadingFailure() {
    guard !Task.isCancelled else { return }
    loadingState = .failed
  }

  // MARK: - Recommendation Hydration

  @ObservationIgnored private var lastObservedCandidates: [CandidateEpisode]?
  @ObservationIgnored private var recommendationHydrationTask: Task<Void, Never>?
  @ObservationIgnored private var hydratedScoreIDs: [Episode.ID] = []

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

  private struct ScoredInputsKey: Equatable, Sendable {
    let candidates: [CandidateEpisode]
    let scoringRevision: Int
  }

  @ObservationIgnored
  private lazy var recommendationCoordinator = RecommendationScoringCoordinator<
    ScoredInputsKey, [Episode.ID: Float]
  >(
    makeSnapshot: { [weak self] in
      guard let self, let candidates = lastObservedCandidates else { return nil }
      return ScoredInputsKey(
        candidates: candidates,
        scoringRevision: recommendationEngine.scoringRevision
      )
    },
    // Errors route to `handleRecommendationFailure` (.failed UI) and return
    // `.cancelled` so no fabricated score is applied.
    score: { [weak self] in
      guard let self, let candidates = lastObservedCandidates, !candidates.isEmpty else {
        return .cacheable([:])
      }
      do {
        return .cacheable(try await recommendationEngine.recommendationScores(for: candidates))
      } catch is CancellationError {
        return .cancelled
      } catch {
        Self.log.caughtError("recommendation scoring failed", error)
        handleRecommendationFailure()
        return .cancelled
      }
    },
    apply: { [weak self] in
      guard let self else { return }
      applyRecommendationScores($0)
    }
  )

  private func applyRecommendationScores(_ scores: [Episode.ID: Float]) {
    Self.log.debug("Recommendation scoring landed \(scores.count) scores")
    guard currentSortMethod == .recommendationScore else { return }
    startRecommendationHydration(for: topEpisodeIDsByScore(from: scores))
  }

  private func handleRecommendationFailure() {
    guard !Task.isCancelled else { return }
    guard currentSortMethod == .recommendationScore else { return }
    loadingState = .failed
  }

  private func topEpisodeIDsByScore(from scores: [Episode.ID: Float]) -> [Episode.ID] {
    guard !scores.isEmpty else { return [] }
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
    markSeen()
  }

  // Advances this list's unread watermark to the newest episode on leave, so
  // everything visited (including episodes that arrived mid-session) clears its
  // hub badge. Fire-and-forget housekeeping: a failure only leaves a stale
  // badge, so it logs without surfacing an alert.
  private func markSeen() {
    // Capture by value, not [weak self]: the view model can deallocate during
    // teardown before this runs, and the watermark write must still complete.
    Task { [smartListRepo, smartListID, title] in
      do {
        try await smartListRepo.markSeen(smartListID)
      } catch {
        Self.log.caughtError("markSeen: failed for '\(title)'", error)
      }
    }
  }

  // The coordinator's score cache deliberately survives teardown.
  private func cancelRecommendationWork() {
    recommendationCoordinator.cancel()
    lastObservedCandidates = nil
    cancelRecommendationHydration()
  }

  private func cancelRecommendationHydration() {
    recommendationHydrationTask?.cancel()
    recommendationHydrationTask = nil
    hydratedScoreIDs = []
  }
}
