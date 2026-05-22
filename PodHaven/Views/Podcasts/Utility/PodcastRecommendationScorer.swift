// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging
import Observation
import Tagged

// Owns recommendation-score sorting for `PodcastDetailViewModel`. Scoring runs
// purely on demand while the `.recommendationScore` sort is selected; the last
// computed score is retained so an unchanged re-selection applies instantly.
@Observable @MainActor
final class PodcastRecommendationScorer {
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  @ObservationIgnored weak var host: (any RecommendationScoringHost)?

  enum Display: Sendable {
    case idle
    case computing
  }
  private(set) var display: Display = .idle

  // MARK: - State

  @ObservationIgnored private var unsavedEmbeddingCache:
    (revision: Int, vectors: [MediaGUID: (source: String, vector: [Float])])?

  @ObservationIgnored
  private lazy var coordinator = RecommendationScoringCoordinator<
    RecommendationScoringSnapshot, [MediaGUID: Float]
  >(
    makeSnapshot: { [weak self] in
      guard let self, let host, host.isSortingByRecommendationScore else { return nil }
      if case .initial = host.state { return nil }
      return currentScoringSnapshot(host: host)
    },
    willScore: { [weak self] in
      guard let self else { return }
      display = .computing
    },
    score: { [weak self] in
      guard let self else { return [:] }
      return await computeRecommendationScores()
    },
    // An unsaved pass that ran before embedding assets finished downloading
    // produced a provisional empty map; caching it would re-apply that map
    // on the next refresh even after the assets land. Recovery relies on a
    // later state or `$scoringRevision` change to retrigger — `assetsLoaded`
    // has no dedicated observer wired here.
    shouldCache: { [weak self] in
      guard let self, let host else { return false }
      if case .unsaved = host.state {
        return contextualEmbedding.assetsLoaded.isFinished
      }
      return true
    },
    apply: { [weak self] in
      guard let self else { return }
      applyComputedScores($0)
    }
  )

  // MARK: - Host Events

  func applyRecommendationSort() {
    guard let host else { return }
    host.episodeList.filterMethod = host.recommendationFallbackFilter
    coordinator.startObservingScoringRevision()
    coordinator.refresh()
  }

  func clearRecommendationSort() {
    display = .idle
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

  private func computeRecommendationScores() async -> [MediaGUID: Float] {
    guard let host else { return [:] }
    let entries = host.episodeList.allEntries
    guard !entries.isEmpty else { return [:] }

    switch host.state {
    case .initial:
      return [:]
    case .saved(let series):
      return await savedRecommendationScores(podcastID: series.id, entries: entries)
    case .unsaved:
      return await unsavedSimilarityScores(entries: entries)
    }
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

  private func applyComputedScores(_ valuesByMediaGUID: [MediaGUID: Float]) {
    guard let host else { return }
    applyRecommendationDisplay(valuesByMediaGUID, host: host)
    display = .idle
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
