// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

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
    } catch {
      Self.log.caughtError(
        "startObservation: observation failed for episode list '\(title)'",
        error
      )
    }
  }

  private func runStandardSortObservation() async throws {
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
    let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
      observatory.listablePodcastEpisodes(
        filter: filter && textSearchFilter && Episode.hasEmbedding
      )
    for try await rows in observation {
      try Task.checkCancellation()

      let currentCandidateIDs = Set(rows.map(\.id))
      if let lastScoredCandidateIDs, currentCandidateIDs != lastScoredCandidateIDs {
        self.lastScoredCandidateIDs = currentCandidateIDs
        kickRecommendationFetch()
      }

      lastObservedCandidateRows = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
      applyOrderedEpisodes()
      if case .loaded = recommendationScoresState { loadingState = .ready }
    }
  }

  private func applyOrderedEpisodes() {
    let topIDs = topEpisodeIDsByScore()
    var ordered = [ListablePodcastEpisode](capacity: topIDs.count)
    for id in topIDs {
      guard let row = lastObservedCandidateRows[id] else { continue }
      ordered.append(row)
    }
    episodeList.allEntries = IdentifiedArray(uniqueElements: ordered)
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
  @ObservationIgnored private var lastScoredCandidateIDs: Set<Episode.ID>?
  @ObservationIgnored
  private var lastObservedCandidateRows: [Episode.ID: ListablePodcastEpisode] = [:]
  @ObservationIgnored private var recommendationObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationFetchTask: Task<Void, Never>?

  private func startRecommendationObservation() {
    if let recommendationObservationTask, !recommendationObservationTask.isCancelled { return }
    recommendationObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      for await _ in recommendationEngine.$contextRevision.stream() {
        guard !Task.isCancelled else { return }
        self.kickRecommendationFetch()
      }
    }
  }

  private func kickRecommendationFetch() {
    recommendationFetchTask?.cancel()
    recommendationFetchTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await self.fetchAndApplyRecommendationScores()
    }
  }

  private func fetchAndApplyRecommendationScores() async {
    let baseFilter = filter && textSearchFilter
    let candidates: [CandidateEpisode]
    do {
      candidates = try await recommendationRepo.candidateEpisodes(filter: baseFilter)
    } catch {
      Self.log.caughtError(
        "fetchAndApplyRecommendationScores: candidate fetch failed",
        error
      )
      applyFailedScores()
      return
    }

    guard !Task.isCancelled else { return }

    let scoreMap: [Episode.ID: RecommendationScore]
    if candidates.isEmpty {
      scoreMap = [:]
    } else {
      do {
        scoreMap = try await recommendationEngine.recommendations(for: candidates)
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
    lastScoredCandidateIDs = Set(candidates.map(\.id))
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
    applyOrderedEpisodes()
    loadingState = .ready
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
    recommendationObservationTask?.cancel()
    recommendationObservationTask = nil
    recommendationFetchTask?.cancel()
    recommendationFetchTask = nil
    lastScoredCandidateIDs = nil
    lastObservedCandidateRows = [:]
  }
}
