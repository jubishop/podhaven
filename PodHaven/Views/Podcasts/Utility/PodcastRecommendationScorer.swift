// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Observation
import Tagged

// Owns recommendation-score sorting for `PodcastDetailViewModel`: observes the
// engine's scoring revisions, computes per-episode scores (saved podcasts via
// the recommendation engine, unsaved ones via on-device similarity), and
// installs the resulting sort/filter onto the host's episode list. The host
// forwards lifecycle and sort/state events here and reads `display` back.
@Observable @MainActor
final class PodcastRecommendationScorer {
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  @ObservationIgnored weak var host: (any RecommendationScoringHost)?

  enum Display: Sendable {
    case idle
    case computing
  }
  private(set) var display: Display = .idle

  // MARK: - State

  @ObservationIgnored private var recommendationObservationTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationScoreTask: Task<Void, Never>?
  @ObservationIgnored private var lastRecommendationScores: RecommendationScoreCache?
  @ObservationIgnored private var unsavedEmbeddingCache:
    (revision: Int, vectors: [MediaGUID: (source: String, vector: [Float])])?
  @ObservationIgnored private var recommendationScoreGeneration = 0

  // Tristate coalescer. `.runningDirty` means another refresh request landed
  // while a pass was already running — the running pass loops once more once
  // its current iteration finishes.
  private enum ScoringStatus {
    case idle
    case running
    case runningDirty
  }
  @ObservationIgnored private var scoringStatus: ScoringStatus = .idle
  @ObservationIgnored private let recommendationScoresDebounce = Debounce(
    duration: .milliseconds(400),
    priority: .utility
  )

  // MARK: - Lifecycle

  func startObservation() {
    if let recommendationObservationTask, !recommendationObservationTask.isCancelled { return }
    let scoringRevisions = recommendationEngine.$scoringRevision.stream().dropFirst()
    let generation = recommendationScoreGeneration
    scheduleImmediateRecommendationScoreRefresh(generation: generation)
    recommendationObservationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      for await _ in scoringRevisions {
        guard !Task.isCancelled else { return }
        scheduleDebouncedRecommendationScoreRefresh(generation: generation)
      }
    }
  }

  func disappear() {
    recommendationScoreGeneration += 1
    scoringStatus = .idle
    recommendationObservationTask?.cancel()
    recommendationObservationTask = nil
    recommendationScoreTask?.cancel()
    recommendationScoreTask = nil
    recommendationScoresDebounce.cancel()
  }

  // MARK: - Host Events

  // The host switched its sort method to `.recommendationScore`. Reuses cached
  // scores when the snapshot still matches; otherwise kicks an immediate pass.
  func applyRecommendationSort() {
    guard let host else { return }
    if let cached = lastRecommendationScores,
      cached.snapshot == currentScoringSnapshot(host: host),
      cached.state == .readyToDisplay
    {
      applyRecommendationDisplay(cached.scores, host: host)
      display = .idle
    } else {
      host.episodeList.filterMethod = host.recommendationFallbackFilter
      display = .computing
      scheduleImmediateRecommendationScoreRefresh()
    }
  }

  // The host switched its sort method away from `.recommendationScore`.
  func clearDisplay() {
    display = .idle
  }

  // The host transitioned to a new state.
  func stateDidChange() {
    guard let host else { return }
    if host.isSortingByRecommendationScore,
      lastRecommendationScores?.snapshot != currentScoringSnapshot(host: host)
    {
      display = .computing
    }
    scheduleDebouncedRecommendationScoreRefresh()
  }

  // MARK: - Scheduling

  private func scheduleImmediateRecommendationScoreRefresh(
    generation: Int? = nil
  ) {
    let generation = generation ?? recommendationScoreGeneration
    guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
    guard let host else { return }
    if case .initial = host.state { return }
    requestRecommendationScoreRefresh(generation: generation)
  }

  private func scheduleDebouncedRecommendationScoreRefresh(
    generation: Int? = nil
  ) {
    let generation = generation ?? recommendationScoreGeneration
    guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
    recommendationScoresDebounce { [weak self] in
      await self?.requestRecommendationScoreRefresh(generation: generation)
    }
  }

  private func requestRecommendationScoreRefresh(generation: Int) {
    guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
    guard scoringStatus == .idle else {
      scoringStatus = .runningDirty
      return
    }
    scoringStatus = .running
    recommendationScoreTask = Task(priority: taskPriority(.utility)) { [weak self] in
      await self?.runRecommendationScorePasses(generation: generation)
    }
  }

  private func runRecommendationScorePasses(generation: Int) async {
    defer {
      if recommendationScoreGeneration == generation {
        scoringStatus = .idle
      }
    }
    while recommendationScoreGeneration == generation, !Task.isCancelled {
      await computeAndPublishRecommendationScores(generation: generation)
      guard recommendationScoreGeneration == generation,
        !Task.isCancelled,
        scoringStatus == .runningDirty
      else { return }
      scoringStatus = .running
    }
  }

  // MARK: - Snapshot

  private struct RecommendationScoreCache {
    let snapshot: RecommendationScoringSnapshot
    let scores: [MediaGUID: Float]
    let state: State

    enum State {
      case readyToDisplay
      case needsForegroundRefresh
    }
  }

  private struct RecommendationScoringSnapshot: Equatable {
    let scoringRevision: Int
    let state: State
    let entries: Set<Entry>

    enum State: Hashable {
      case initial
      case unsaved(embeddingRevision: Int)
      case saved(Podcast.ID)
    }

    enum Entry: Hashable {
      case saved(mediaGUID: MediaGUID, episodeID: Episode.ID, pubDate: Date)
      case unsaved(mediaGUID: MediaGUID, embeddingSource: String)
      case unscored(mediaGUID: MediaGUID)
    }

    func hasSavedEntriesMissingScores(_ scores: [MediaGUID: Float]) -> Bool {
      for entry in entries {
        switch entry {
        case .saved(let mediaGUID, _, _):
          if scores[mediaGUID] == nil { return true }
        case .unsaved, .unscored:
          continue
        }
      }
      return false
    }
  }

  private func currentScoringSnapshot(
    host: any RecommendationScoringHost
  ) -> RecommendationScoringSnapshot {
    let snapshotState: RecommendationScoringSnapshot.State
    switch host.state {
    case .initial:
      snapshotState = .initial
    case .unsaved:
      snapshotState = .unsaved(embeddingRevision: contextualEmbedding.revision)
    case .saved(let series):
      snapshotState = .saved(series.id)
    }
    return RecommendationScoringSnapshot(
      scoringRevision: recommendationEngine.scoringRevision,
      state: snapshotState,
      entries: Set(host.episodeList.allEntries.map(scoringSnapshotEntry))
    )
  }

  private func scoringSnapshotEntry(
    _ episode: ListedEpisode
  ) -> RecommendationScoringSnapshot.Entry {
    if let episodeID = episode.episodeID {
      return .saved(
        mediaGUID: episode.mediaGUID,
        episodeID: episodeID,
        pubDate: episode.pubDate
      )
    }
    if let unsaved = episode.unsaved {
      return .unsaved(
        mediaGUID: episode.mediaGUID,
        embeddingSource: unsaved.searchableString
      )
    }
    return .unscored(mediaGUID: episode.mediaGUID)
  }

  // MARK: - Scoring

  private func computeAndPublishRecommendationScores(generation: Int) async {
    guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
    guard let host else { return }
    let snapshot = currentScoringSnapshot(host: host)
    let entries = host.episodeList.allEntries
    guard !entries.isEmpty else {
      display = .idle
      return
    }

    if let cached = lastRecommendationScores,
      cached.snapshot == snapshot,
      cached.state == .readyToDisplay
    {
      guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
      guard host.isSortingByRecommendationScore else { return }
      applyRecommendationDisplay(cached.scores, host: host)
      display = .idle
      return
    }

    let valuesByMediaGUID: [MediaGUID: Float]
    switch host.state {
    case .initial:
      display = .idle
      return
    case .saved(let series):
      valuesByMediaGUID = await savedRecommendationScores(
        podcastID: series.id,
        entries: entries
      )
    case .unsaved:
      valuesByMediaGUID = await unsavedSimilarityScores(entries: entries)
    }

    guard recommendationScoreGeneration == generation, !Task.isCancelled else { return }
    guard snapshot == currentScoringSnapshot(host: host) else {
      scoringStatus = .runningDirty
      return
    }
    let cacheState: RecommendationScoreCache.State
    if !host.isSortingByRecommendationScore,
      snapshot.hasSavedEntriesMissingScores(valuesByMediaGUID)
    {
      cacheState = .needsForegroundRefresh
    } else {
      cacheState = .readyToDisplay
    }
    lastRecommendationScores = RecommendationScoreCache(
      snapshot: snapshot,
      scores: valuesByMediaGUID,
      state: cacheState
    )
    guard host.isSortingByRecommendationScore else { return }
    applyRecommendationDisplay(valuesByMediaGUID, host: host)
    display = .idle
  }

  private func savedRecommendationScores(
    podcastID: Podcast.ID,
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async -> [MediaGUID: Float] {
    var candidates = [CandidateEpisode](capacity: entries.count)
    var mediaGUIDByEpisodeID = [Episode.ID: MediaGUID](capacity: entries.count)
    for episode in entries {
      guard let episodeID = episode.episodeID else { continue }
      candidates.append(
        CandidateEpisode(id: episodeID, podcastID: podcastID, pubDate: episode.pubDate)
      )
      mediaGUIDByEpisodeID[episodeID] = episode.mediaGUID
    }
    guard !candidates.isEmpty else { return [:] }

    let scoreMap: [Episode.ID: RecommendationScore]
    do {
      scoreMap = try await recommendationEngine.recommendations(for: candidates)
    } catch {
      Self.log.caughtError(
        "savedRecommendationScores failed for \(candidates.count) ids",
        error
      )
      return [:]
    }

    var result = [MediaGUID: Float](capacity: scoreMap.count)
    for (episodeID, score) in scoreMap {
      guard let mediaGUID = mediaGUIDByEpisodeID[episodeID] else { continue }
      result[mediaGUID] = score.value
    }
    return result
  }

  private func unsavedSimilarityScores(
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async -> [MediaGUID: Float] {
    await contextualEmbedding.loadAssetsIfAvailable()
    guard contextualEmbedding.assetsLoaded.isFinished else { return [:] }

    let revision = contextualEmbedding.revision
    var cachedVectors: [MediaGUID: (source: String, vector: [Float])]
    if let cache = unsavedEmbeddingCache, cache.revision == revision {
      cachedVectors = cache.vectors
    } else {
      cachedVectors = [MediaGUID: (source: String, vector: [Float])](capacity: entries.count)
    }

    var result = [MediaGUID: Float](capacity: entries.count)
    for episode in entries {
      if Task.isCancelled { break }
      guard let unsavedPodcastEpisode = episode.unsaved else { continue }
      let source = unsavedPodcastEpisode.searchableString
      let vector: [Float]
      if let cached = cachedVectors[episode.mediaGUID], cached.source == source {
        vector = cached.vector
      } else {
        do {
          vector = try await EmbeddingService.embeddingVector(
            for: unsavedPodcastEpisode,
            embedding: contextualEmbedding
          )
        } catch {
          Self.log.caughtError(
            """
            unsavedSimilarityScores: embedding failed for \
            \(unsavedPodcastEpisode.toString)
            """,
            error
          )
          continue
        }
        cachedVectors[episode.mediaGUID] = (source: source, vector: vector)
      }
      if let similarity = recommendationEngine.similarityScore(forEmbedding: vector) {
        result[episode.mediaGUID] = similarity
      }
    }

    unsavedEmbeddingCache = (revision: revision, vectors: cachedVectors)
    return result
  }

  private func applyRecommendationDisplay(
    _ valuesByMediaGUID: [MediaGUID: Float],
    host: any RecommendationScoringHost
  ) {
    switch host.state {
    case .saved:
      host.episodeList.filterMethod = { valuesByMediaGUID[$0.mediaGUID] != nil }
    case .unsaved, .initial:
      host.episodeList.filterMethod = host.recommendationFallbackFilter
    }
    host.episodeList.sortMethod = makeRecommendationComparator(valuesByMediaGUID)
  }

  private func makeRecommendationComparator(
    _ valuesByMediaGUID: [MediaGUID: Float]
  ) -> @Sendable (ListedEpisode, ListedEpisode) -> Bool {
    { lhs, rhs in
      let lhsScore = valuesByMediaGUID[lhs.mediaGUID] ?? 0
      let rhsScore = valuesByMediaGUID[rhs.mediaGUID] ?? 0
      if lhsScore != rhsScore { return lhsScore > rhsScore }
      if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
      if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
        return lhs.mediaGUID.guid > rhs.mediaGUID.guid
      }
      return lhs.mediaGUID.mediaURL.rawValue.absoluteString
        > rhs.mediaGUID.mediaURL.rawValue.absoluteString
    }
  }
}
