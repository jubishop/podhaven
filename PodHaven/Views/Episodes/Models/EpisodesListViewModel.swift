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

  // MARK: - Candidate Observation

  // Runs whenever the view is visible, independent of the current sort
  // method. Maintains the top-100 recommendation IDs so that switching to
  // recommendation sort can hydrate immediately instead of waiting for a
  // cold scoring pass.
  func startCandidateObservation() async {
    startRecommendationContextObservation()

    do {
      let observation: AsyncValueObservation<[CandidateEpisode]> =
        observatory.embeddedCandidateEpisodes(filter: filter && textSearchFilter)
      for try await candidates in observation {
        try Task.checkCancellation()

        lastObservedCandidates = candidates
        kickRecommendationFetch(candidates: candidates)
        kickRecommendationHydration()
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "startCandidateObservation: observation failed for episode list '\(title)'",
        error
      )
      handleRecommendationFailure()
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
        kickRecommendationHydration()
      } else {
        try await runStandardSortObservation()
      }
    } catch is CancellationError {
    } catch {
      Self.log.caughtError(
        "startDisplayObservation: observation failed for episode list '\(title)'",
        error
      )
      handleLoadingFailure()
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
      transitionToLoaded(podcastEpisodes)
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

  // MARK: - Recommendation Observation

  @ObservationIgnored private var lastObservedCandidates: [CandidateEpisode]?
  @ObservationIgnored private var recommendationContextObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationHydrationTask: Task<Void, Never>?
  @ObservationIgnored private var hydratedScoreIDs: [Episode.ID] = []

  private func startRecommendationContextObservation() {
    if let recommendationContextObservationTask, !recommendationContextObservationTask.isCancelled {
      return
    }
    recommendationContextObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      // Drop the first emission — $scoringRevision yields its current value
      // on subscribe, and the candidate observation's first emission is what
      // kicks the initial fetch. Skipping it here avoids double-fetching on
      // view appear.
      for await _ in self.recommendationEngine.$scoringRevision.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        self.kickRecommendationFetch(candidates: self.lastObservedCandidates)
      }
    }
  }

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
  @ObservationIgnored private var recommendationFetchTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationFetchGeneration = 0
  @ObservationIgnored private let recommendationFetchDebounce = Debounce(
    duration: .milliseconds(400)
  )

  private func kickRecommendationFetch(candidates observedCandidates: [CandidateEpisode]?) {
    // The candidate observation is the sole source of truth for which episodes
    // to score. If it hasn't emitted yet (a context-revision tick can race
    // ahead of the first observation yield on view appear), skip this kick —
    // the imminent first candidate emission will call us back with fresh data.
    guard let candidates = observedCandidates else { return }

    let key = ScoredInputsKey(
      candidates: candidates,
      scoringRevision: recommendationEngine.scoringRevision
    )
    // Skip when neither the candidates nor the engine's scoring context changed.
    guard key != lastScoredKey else { return }

    // A pass is in flight — coalesce further kicks into one trailing pass.
    // The trailing kick re-reads the latest observed candidates at fire time
    // instead of capturing this kick's set, so it can't rescan a stale
    // snapshot after a newer pass already scored fresher candidates — and it
    // no-ops after disappear, when lastObservedCandidates is nil.
    guard recommendationFetchTask == nil else {
      recommendationFetchDebounce { @MainActor [weak self] in
        guard let self else { return }
        self.kickRecommendationFetch(candidates: self.lastObservedCandidates)
      }
      return
    }

    recommendationFetchGeneration += 1
    let generation = recommendationFetchGeneration
    recommendationFetchTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      // Clear the slot only if a newer pass hasn't already replaced this task.
      defer {
        if self.recommendationFetchGeneration == generation {
          self.recommendationFetchTask = nil
        }
      }
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
            "kickRecommendationFetch: scoring failed",
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
    cancelRecommendationContextObservation()
    cancelRecommendationFetch()
    cancelRecommendationHydration()
  }

  private func cancelRecommendationContextObservation() {
    recommendationContextObservationTask?.cancel()
    recommendationContextObservationTask = nil
  }

  private func cancelRecommendationFetch() {
    recommendationFetchTask?.cancel()
    recommendationFetchTask = nil
    recommendationFetchDebounce.cancel()
    lastObservedCandidates = nil
    // lastScoredKey is deliberately kept so a completed score survives a tab switch.
  }

  private func cancelRecommendationHydration() {
    recommendationHydrationTask?.cancel()
    recommendationHydrationTask = nil
    hydratedScoreIDs = []
  }
}
