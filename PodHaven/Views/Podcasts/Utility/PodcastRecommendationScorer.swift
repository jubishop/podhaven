// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Observation
import Tagged

// Owns recommendation-score sorting for `PodcastDetailViewModel`. Scoring runs
// purely on demand: `applyRecommendationSort()` is the sole entry point, fired
// when the host selects the `.recommendationScore` sort. While that sort is
// selected the scorer observes the engine's scoring revisions and the host's
// state changes and rescores; outside it, nothing runs. Scoring computes
// per-episode scores (saved podcasts via the recommendation engine, unsaved
// ones via on-device similarity) and installs the resulting sort/filter onto
// the host's episode list. The last computed score is retained so re-selecting
// the sort with an unchanged candidate set applies instantly.
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

  @ObservationIgnored private var scoringRevisionTask: Task<Void, Never>?
  @ObservationIgnored private var recommendationScoreTask: Task<Void, Never>?
  @ObservationIgnored private var lastRecommendationScores: RecommendationScoreCache?
  @ObservationIgnored private var unsavedEmbeddingCache:
    (revision: Int, vectors: [MediaGUID: (source: String, vector: [Float])])?

  // MARK: - Host Events

  // The host switched its sort method to `.recommendationScore`, or the view
  // reappeared with that sort still selected. Reuses the retained score when
  // the snapshot still matches; otherwise kicks an immediate pass behind a
  // "Computing recommendations…" banner.
  func applyRecommendationSort() {
    guard let host else { return }
    startScoringRevisionObservation()
    if let cached = lastRecommendationScores,
      cached.snapshot == currentScoringSnapshot(host: host)
    {
      applyRecommendationDisplay(cached.scores, host: host)
      display = .idle
    } else {
      host.episodeList.filterMethod = host.recommendationFallbackFilter
      display = .computing
      recompute()
    }
  }

  // The host switched its sort method away from `.recommendationScore`. The
  // retained score survives so a later re-selection can skip recomputing.
  func clearDisplay() {
    display = .idle
    cancelScoring()
  }

  // The host transitioned to a new state. A rescore is only relevant while the
  // rec sort is the selected one.
  func stateDidChange() {
    guard let host, host.isSortingByRecommendationScore else { return }
    if lastRecommendationScores?.snapshot != currentScoringSnapshot(host: host) {
      display = .computing
    }
    recompute()
  }

  // The view disappeared. The retained score survives teardown.
  func disappear() {
    cancelScoring()
  }

  // MARK: - Scoring Lifecycle

  private func startScoringRevisionObservation() {
    if let scoringRevisionTask, !scoringRevisionTask.isCancelled { return }
    // Drop the first emission — $scoringRevision replays its current value on
    // subscribe, and applyRecommendationSort() already kicks the initial pass.
    let scoringRevisions = recommendationEngine.$scoringRevision.stream().dropFirst()
    scoringRevisionTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      for await _ in scoringRevisions {
        guard !Task.isCancelled else { return }
        recompute()
      }
    }
  }

  private func cancelScoring() {
    scoringRevisionTask?.cancel()
    scoringRevisionTask = nil
    recommendationScoreTask?.cancel()
    recommendationScoreTask = nil
  }

  // Cancel-and-restart: a new request cancels any in-flight pass, so the
  // latest inputs win and a superseded pass never publishes.
  private func recompute() {
    guard let host, host.isSortingByRecommendationScore else { return }
    if case .initial = host.state { return }
    recommendationScoreTask?.cancel()
    recommendationScoreTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await computeAndPublishRecommendationScores()
    }
  }

  // MARK: - Snapshot

  private struct RecommendationScoreCache {
    let snapshot: RecommendationScoringSnapshot
    let scores: [MediaGUID: Float]
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

  private func computeAndPublishRecommendationScores() async {
    guard let host else { return }
    let snapshot = currentScoringSnapshot(host: host)
    let entries = host.episodeList.allEntries
    guard !entries.isEmpty else {
      display = .idle
      return
    }

    if let cached = lastRecommendationScores, cached.snapshot == snapshot {
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

    guard !Task.isCancelled else { return }
    lastRecommendationScores = RecommendationScoreCache(
      snapshot: snapshot,
      scores: valuesByMediaGUID
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
