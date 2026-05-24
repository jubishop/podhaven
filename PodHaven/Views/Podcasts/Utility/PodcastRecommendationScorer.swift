// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Tagged

// Owns recommendation-score sorting for `PodcastDetailViewModel`. Scoring runs
// purely on demand while the `.recommendationScore` sort is selected; the last
// computed score is retained so an unchanged re-selection applies instantly.
@MainActor
final class PodcastRecommendationScorer {
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  weak var host: PodcastDetailViewModel?

  // MARK: - State

  private var unsavedEmbeddingCache:
    (revision: Int, vectors: [MediaGUID: (source: String, vector: [Float])])?

  private lazy var coordinator = RecommendationScoringCoordinator<
    RecommendationScoringSnapshot, [MediaGUID: Float]
  >(
    makeSnapshot: { [weak self] in
      guard let self, let host, host.currentSortMethod == .recommendationScore else {
        return nil
      }
      if case .initial = host.state { return nil }
      return currentScoringSnapshot(host: host)
    },
    // An unsaved pass that ran before embedding assets finished downloading
    // returns the empty map as uncacheable; caching it would re-apply that
    // map on the next refresh even after the assets land. The helper
    // classifies cacheability at its observation point so a latch that
    // finishes between helper return and the closure can't flip the policy.
    // The coordinator's `refreshOnAssetsLoaded` observer recovers once the
    // latch finishes.
    //
    // Errors map to .uncacheable([:]): the comparator falls back to tiebreaker
    // order for this pass, and the next refresh re-attempts instead of
    // replaying a cached transient failure.
    score: { [weak self] in
      guard let self else { return .cacheable([:]) }
      do {
        let (result, cacheable) = try await computeRecommendationScores()
        return cacheable ? .cacheable(result) : .uncacheable(result)
      } catch is CancellationError {
        return .cancelled
      } catch {
        Self.log.caughtError("recommendation scoring failed", error)
        return .uncacheable([:])
      }
    },
    apply: { [weak self] in
      guard let self else { return }
      applyComputedScores($0)
    },
    refreshOnAssetsLoaded: true
  )

  // MARK: - Host Events

  func applyRecommendationSort() {
    guard host != nil else { return }
    coordinator.startObservations()
    coordinator.refresh()
  }

  func clearRecommendationSort() {
    coordinator.cancel()
  }

  func stateDidChange() {
    coordinator.refresh()
  }

  func disappear() {
    coordinator.cancel()
  }

  // MARK: - Snapshot

  private struct RecommendationScoringSnapshot: Equatable, Sendable {
    let scoringRevision: Int
    let state: State
    let entries: Set<Entry>

    enum State: Hashable, Sendable {
      case initial
      case unsaved(embeddingRevision: Int)
      case saved(Podcast.ID)
    }

    enum Entry: Hashable, Sendable {
      case saved(mediaGUID: MediaGUID, episodeID: Episode.ID, pubDate: Date)
      case unsaved(mediaGUID: MediaGUID, embeddingSource: String)
      case unscored(mediaGUID: MediaGUID)
    }
  }

  private func currentScoringSnapshot(
    host: PodcastDetailViewModel
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

  private func computeRecommendationScores() async throws -> (
    [MediaGUID: Float], cacheable: Bool
  ) {
    guard let host else { return ([:], true) }
    let entries = host.episodeList.allEntries
    guard !entries.isEmpty else { return ([:], true) }

    switch host.state {
    case .initial:
      return ([:], true)
    case .saved(let series):
      return (try await savedRecommendationScores(podcastID: series.id, entries: entries), true)
    case .unsaved:
      return try await unsavedSimilarityScores(entries: entries)
    }
  }

  private func savedRecommendationScores(
    podcastID: Podcast.ID,
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async throws -> [MediaGUID: Float] {
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

    let scoreMap = try await recommendationEngine.recommendations(for: candidates)

    var result = [MediaGUID: Float](capacity: scoreMap.count)
    for (episodeID, score) in scoreMap {
      guard let mediaGUID = mediaGUIDByEpisodeID[episodeID] else { continue }
      result[mediaGUID] = score.value
    }
    return result
  }

  private func unsavedSimilarityScores(
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async throws -> ([MediaGUID: Float], cacheable: Bool) {
    await contextualEmbedding.loadAssetsIfAvailable()
    // Classify cacheability at the same point we observe asset state so a
    // latch that finishes after this guard can't flip the closure's decision.
    guard contextualEmbedding.assetsLoaded.isFinished else { return ([:], false) }

    let revision = contextualEmbedding.revision
    var cachedVectors: [MediaGUID: (source: String, vector: [Float])]
    if let cache = unsavedEmbeddingCache, cache.revision == revision {
      cachedVectors = cache.vectors
    } else {
      cachedVectors = [MediaGUID: (source: String, vector: [Float])](capacity: entries.count)
    }

    var result = [MediaGUID: Float](capacity: entries.count)
    for episode in entries {
      try Task.checkCancellation()
      guard let unsavedPodcastEpisode = episode.unsaved else { continue }
      let source = unsavedPodcastEpisode.searchableString
      let vector: [Float]
      if let cached = cachedVectors[episode.mediaGUID], cached.source == source {
        vector = cached.vector
      } else {
        vector = try await EmbeddingService.embeddingVector(
          for: unsavedPodcastEpisode,
          embedding: contextualEmbedding
        )
        cachedVectors[episode.mediaGUID] = (source: source, vector: vector)
      }
      if let similarity = recommendationEngine.similarityScore(forEmbedding: vector) {
        result[episode.mediaGUID] = similarity
      }
    }

    unsavedEmbeddingCache = (revision: revision, vectors: cachedVectors)
    return (result, true)
  }

  private func applyComputedScores(_ valuesByMediaGUID: [MediaGUID: Float]) {
    guard let host else { return }
    applyRecommendationDisplay(valuesByMediaGUID, host: host)
  }

  private func applyRecommendationDisplay(
    _ valuesByMediaGUID: [MediaGUID: Float],
    host: PodcastDetailViewModel
  ) {
    switch host.state {
    case .saved:
      host.episodeList.filterMethod = { valuesByMediaGUID[$0.mediaGUID] != nil }
    case .unsaved, .initial:
      host.episodeList.filterMethod = host.currentSortMethod.filterMethod
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
