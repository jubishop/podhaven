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
      default: return AppDB.noOp
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
      .reduce(AppDB.noOp) { $0 && $1 }
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
  let title: String
  let filter: SQLExpression
  private(set) var loadingState: LoadingState = .loading

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

  init(title: String, filter: SQLExpression = AppDB.noOp) {
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
