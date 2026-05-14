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
        // Display order is decided in memory from `lastRecommendationScores`
        // (see `runRecommendationSortObservation`), so there's no
        // meaningful SQL ordering to assert here.
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

  let title: String
  let filter: SQLExpression
  private(set) var isLoading = true

  // Display cap. Non-rec sorts let SQLite enforce it via `LIMIT`; the rec
  // sort enforces it in memory after ranking the cached score map.
  private static let displayLimit = 100

  @ObservationIgnored private var lastObservationKey: String?
  var observationKey: String {
    // `recommendationScoresVersion` participates only on the rec sort path:
    // that's the path whose displayed top-N set has to roll forward when
    // the scoring task lands a fresh map. Non-rec sorts ignore it so a
    // context-revision tick doesn't pointlessly restart their SQL
    // observation.
    let recPart =
      currentSortMethod == .recommendationScore ? "-\(recommendationScoresVersion)" : ""
    return "\(currentSortMethod.rawValue)-\(filterText)\(recPart)"
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

    if keyChanged || episodeList.allEntries.isEmpty { isLoading = true }
    defer { isLoading = false }

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
      isLoading = false
    }
  }

  // Recommendation sort runs on top of the scoring pipeline started by
  // `startRecommendationObservation`: scores are computed against every
  // matching candidate in the background, we read the cached top-N IDs,
  // and the SQL observation here is narrowed to just those rows. Toggling
  // is instant once `lastRecommendationScores` has landed.
  private func runRecommendationSortObservation() async throws {
    await awaitRecommendationScores()
    try Task.checkCancellation()

    let topIDs = topEpisodeIDsByScore()
    guard !topIDs.isEmpty else {
      episodeList.allEntries = []
      isLoading = false
      return
    }

    let observation: AsyncValueObservation<[ListablePodcastEpisode]> =
      observatory.listablePodcastEpisodes(
        filter: topIDs.contains(Episode.Columns.id),
        // SQL ordering is irrelevant here — `topIDs` already encodes the
        // score order and the loop below restores it after each emit.
        order: Episode.Columns.pubDate.desc,
        limit: topIDs.count
      )
    for try await rows in observation {
      try Task.checkCancellation()
      let rowsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
      var ordered = [ListablePodcastEpisode](capacity: topIDs.count)
      for id in topIDs {
        guard let row = rowsByID[id] else { continue }
        ordered.append(row)
      }
      episodeList.allEntries = IdentifiedArray(uniqueElements: ordered)
      isLoading = false
    }
  }

  // MARK: - Recommendation Scoring

  // Bumped after each scoring pass that lands a non-initial map; participates
  // in `observationKey` so the rec-sort display observation restarts against
  // the new top-N IDs.
  private var recommendationScoresVersion: Int = 0

  @ObservationIgnored private var lastRecommendationScores: [Episode.ID: Float]?
  @ObservationIgnored private var recommendationObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationScoresLoaded = false
  @ObservationIgnored private var recommendationScoresAwaiters: [CheckedContinuation<Void, Never>] =
    []

  private func startRecommendationObservation() {
    if let recommendationObservationTask, !recommendationObservationTask.isCancelled { return }
    recommendationObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      for await _ in recommendationEngine.$contextRevision.stream() {
        guard !Task.isCancelled else { return }
        await fetchAndApplyRecommendationScores()
      }
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
      // Unblock any rec-sort awaiter even when we have nothing to give it,
      // so it can fall back to an empty list instead of waiting forever.
      signalRecommendationScoresLoaded()
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
        signalRecommendationScoresLoaded()
        return
      }
    }

    guard !Task.isCancelled else { return }

    let isFirstLoad = !recommendationScoresLoaded
    var values = [Episode.ID: Float](capacity: scoreMap.count)
    for (id, score) in scoreMap { values[id] = score.value }
    lastRecommendationScores = values
    Self.log.debug(
      "Recommendation scoring landed \(values.count) scores for \(candidates.count) candidates"
    )
    signalRecommendationScoresLoaded()
    // Skip the version bump on the very first load: the rec-sort task is
    // already awaiting `signalRecommendationScoresLoaded` and will pick up
    // the fresh scores when it resumes. Bumping would just cancel and
    // restart the work we're about to do.
    if !isFirstLoad { recommendationScoresVersion += 1 }
  }

  private func signalRecommendationScoresLoaded() {
    recommendationScoresLoaded = true
    let continuations = recommendationScoresAwaiters
    recommendationScoresAwaiters.removeAll()
    for continuation in continuations { continuation.resume() }
  }

  private func awaitRecommendationScores() async {
    if recommendationScoresLoaded { return }
    await withCheckedContinuation { continuation in
      recommendationScoresAwaiters.append(continuation)
    }
  }

  private func topEpisodeIDsByScore() -> [Episode.ID] {
    guard let scores = lastRecommendationScores, !scores.isEmpty else { return [] }
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
    for continuation in recommendationScoresAwaiters { continuation.resume() }
    recommendationScoresAwaiters.removeAll()
  }
}
