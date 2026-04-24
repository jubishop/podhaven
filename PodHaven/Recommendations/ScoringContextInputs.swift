// Copyright Justin Bishop, 2026

import Foundation

// Snapshot of all DB state that feeds RecommendationEngine.ScoringContext.
// Emitted by `Observatory.scoringContextInputs()` on every relevant change so
// the engine rebuilds its cached context once per change instead of once per
// recommendation request.
struct ScoringContextInputs: Sendable, Equatable {
  let signals: [Signal]
  let signalEmbeddings: [Episode.ID: EmbeddingVector]
  let hasAnyEmbeddings: Bool

  // Subset of Episode used for centroid + affinity math. Manual projection
  // keeps the observation Equatable (required by `removeDuplicates()`)
  // without forcing Equatable on Episode/UnsavedEpisode.
  struct Signal: Sendable, Equatable, Identifiable {
    let id: Episode.ID
    let podcastID: Podcast.ID
    let kind: SignalKind
    let ratingDate: Date?
    let finishDate: Date?

    init(from episode: Episode) {
      self.id = episode.id
      self.podcastID = episode.podcastID
      if let rating = episode.rating {
        self.kind = .rating(rating)
      } else {
        self.kind = .finished
      }
      self.ratingDate = episode.ratingDate
      self.finishDate = episode.finishDate
    }
  }

  // Same on-the-wire vector + dimension EpisodeEmbedding holds, minus the
  // metadata (id, creationDate, sourceHash, embeddingRevision) the engine
  // never reads — keeps the diffed payload small.
  struct EmbeddingVector: Sendable, Equatable, VectorStorable {
    let vector: Data
    let dimension: Int

    init(from embedding: EpisodeEmbedding) {
      self.vector = embedding.vector
      self.dimension = embedding.dimension
    }
  }
}
