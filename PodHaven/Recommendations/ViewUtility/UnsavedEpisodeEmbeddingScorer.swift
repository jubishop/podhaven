// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Per-host helper that computes similarity scores for unsaved episodes
// against the recommendation engine's centroid. Owns a revision-keyed,
// per-`MediaGUID` vector cache so repeated scoring passes (sort recompute,
// list refresh) don't recompute the same vector.
//
// `cacheable: false` means the contextual embedding model hasn't finished
// loading. Callers route that through `RecommendationScoringCoordinator`'s
// `.uncacheable` arm so the empty result isn't memoized and the next refresh
// retries once the assets-loaded latch fires.
@MainActor
final class UnsavedEpisodeEmbeddingScorer {
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine

  private struct Cache {
    let revision: Int
    var vectors: [MediaGUID: (source: String, vector: [Float])]
  }

  private var cache: Cache?

  func similarityScore(
    for unsavedEpisode: UnsavedPodcastEpisode
  ) async throws -> (score: Float?, cacheable: Bool) {
    let (scores, cacheable) = try await similarityScores(for: CollectionOfOne(unsavedEpisode))
    return (scores[unsavedEpisode.mediaGUID], cacheable)
  }

  func similarityScores(
    for unsavedEpisodes: some Sequence<UnsavedPodcastEpisode>
  ) async throws -> (scores: [MediaGUID: Float], cacheable: Bool) {
    await contextualEmbedding.loadAssetsIfAvailable()
    guard contextualEmbedding.assetsLoaded.isOpen else { return ([:], false) }

    let revision = contextualEmbedding.revision
    let capacity = unsavedEpisodes.underestimatedCount
    var cachedVectors: [MediaGUID: (source: String, vector: [Float])]
    if let cache, cache.revision == revision {
      cachedVectors = cache.vectors
    } else {
      cachedVectors = [MediaGUID: (source: String, vector: [Float])](capacity: capacity)
    }

    var scores = [MediaGUID: Float](capacity: capacity)
    for episode in unsavedEpisodes {
      try Task.checkCancellation()
      let mediaGUID = episode.mediaGUID
      let source = episode.searchableString
      let vector: [Float]
      if let cached = cachedVectors[mediaGUID], cached.source == source {
        vector = cached.vector
      } else {
        vector = try await EmbeddingService.embeddingVector(
          for: episode,
          embedding: contextualEmbedding
        )
        cachedVectors[mediaGUID] = (source: source, vector: vector)
      }
      if let similarity = recommendationEngine.similarityScore(forEmbedding: vector) {
        scores[mediaGUID] = similarity
      }
    }

    cache = Cache(revision: revision, vectors: cachedVectors)
    return (scores, true)
  }
}
