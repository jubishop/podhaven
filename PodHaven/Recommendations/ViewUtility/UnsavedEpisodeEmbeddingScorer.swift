// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Tagged

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

    var orderedGUIDs = [MediaGUID](capacity: capacity)
    var vectors = [[Float]](capacity: capacity)
    // The podcast-context vector is identical for every episode of a feed, so
    // compute it once per feed instead of re-embedding it on each cache miss.
    var podcastVectors: [FeedURL: [Float]?] = [:]
    for episode in unsavedEpisodes {
      try Task.checkCancellation()
      let mediaGUID = episode.mediaGUID
      let source = episode.searchableString
      let vector: [Float]
      if let cached = cachedVectors[mediaGUID], cached.source == source {
        vector = cached.vector
      } else {
        let feedURL = episode.feedURL
        let podcastVector: [Float]?
        if let cached = podcastVectors[feedURL] {
          podcastVector = cached
        } else {
          podcastVector = try await EmbeddingService.podcastContextVector(
            for: episode.unsavedPodcast,
            embedding: contextualEmbedding
          )
          podcastVectors[feedURL] = podcastVector
        }
        vector = try await EmbeddingService.episodeEmbeddingVector(
          for: episode.unsavedEpisode,
          podcastVector: podcastVector,
          embedding: contextualEmbedding
        )
        cachedVectors[mediaGUID] = (source: source, vector: vector)
      }
      orderedGUIDs.append(mediaGUID)
      vectors.append(vector)
    }

    cache = Cache(revision: revision, vectors: cachedVectors)

    // One hop off the main actor: the vDSP scoring loop runs on the cooperative
    // pool instead of a synchronous per-vector call per episode here.
    let similarities = try await recommendationEngine.similarityScores(forEmbeddings: vectors)
    var scores = [MediaGUID: Float](capacity: capacity)
    for (mediaGUID, similarity) in zip(orderedGUIDs, similarities) {
      guard let similarity else { continue }
      scores[mediaGUID] = similarity
    }
    return (scores, true)
  }
}
