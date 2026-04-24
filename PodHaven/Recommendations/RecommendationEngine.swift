// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

// MARK: - Types

// The "new info" a recommendation adds to an episode: a blended score in
// [0, 1] and the reasons that fired above their neutral midpoint. Returned
// on its own by `recommendations(for:)` so callers that already have the
// episodes don't get them echoed back.
struct RecommendationScore: Sendable {
  let value: Float
  let reasons: [RecommendationReason]
}

// Pairs an episode with its score, used by `topRecommendations` where the
// caller doesn't have the episodes up front.
struct RecommendedEpisode: Sendable, Identifiable {
  var id: Episode.ID { episode.id }
  let episode: Episode
  let score: RecommendationScore
}

enum RecommendationReason: Sendable {
  case similarToLiked
  case podcastAffinity
  case recentlyPublished
}

// MARK: - Container

extension Container {
  var recommendationEngine: Factory<RecommendationEngine> {
    Factory(self) { RecommendationEngine() }.scope(.cached)
  }
}

// MARK: - RecommendationEngine

struct RecommendationEngine: Sendable {
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Recommendations.engine)

  private static let minimumDataThreshold = 3
  private static let minimumScoreThreshold: Float = 0.1

  // Scoring weights (must sum to 1.0)
  private static let similarityWeight: Float = 0.60
  private static let podcastAffinityWeight: Float = 0.20
  private static let freshnessWeight: Float = 0.20

  // Freshness curve: `1 / (1 + days / midpoint)`. This is a hyperbolic decay,
  // not an exponential half-life — it crosses 0.5 once at `midpoint` days and
  // then tapers slowly (120d → 0.33, 180d → 0.25, 365d → 0.14). 60 days is
  // tuned for the "haven't configured anything" default — most podcast
  // subscriptions are time-sensitive enough that 2-month-old episodes scoring
  // 0.5 feels right. Evergreen/history content gets overridden per-podcast
  // (see memory: ML Recommendations Feature → deferred to v2).
  private static let freshnessMidpointDays: Double = 60

  // Centroid weights
  private static let lovedWeight: Float = 1.0
  private static let likedWeight: Float = 0.5
  private static let finishedWeight: Float = 0.2

  // Bayesian smoothing prior for podcast affinity
  private static let affinityPrior: Float = 2.0

  // Podcast affinity — dislikes contribute but at half the strength of likes.
  // One bad episode shouldn't tank an otherwise-loved show, but repeated
  // dislikes should still register as show-level aversion.
  private static let dislikedAffinityWeight: Float = 0.5

  // Temporal decay half-life in days
  private static let decayHalfLifeDays: Double = 180

  // MARK: - Public API

  // Score an arbitrary set of episodes so a caller can sort a list by "how
  // recommended." Unlike `topRecommendations`, there's no candidate filter,
  // no minimum-score floor, and no limit — every requested episode that has
  // sufficient context gets a score. Callers already have the episodes, so
  // we return just the new info (score + reasons) keyed by ID.
  func recommendations(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    guard !episodes.isEmpty else { return [:] }
    guard let context = try await prepareScoringContext() else { return [:] }
    return try await scoreEpisodes(episodes, context: context)
  }

  func topRecommendations(limit: Int = 10) async throws -> IdentifiedArrayOf<RecommendedEpisode> {
    Self.log.debug("Generating top recommendations (limit: \(limit))")
    let onDeckID = Container.shared.sharedState().onDeck?.id
    let candidates = try await repo.allCandidateEpisodes(excluding: onDeckID)
    let scores = try await recommendations(for: candidates)

    // Join episodes with their scores, dropping anything below the confidence
    // floor. Filter is O(n); shrinking the list before sorting makes the
    // O(n log n) sort cheaper.
    var results = [RecommendedEpisode](capacity: candidates.count)
    for episode in candidates {
      guard let score = scores[episode.id],
        score.value >= Self.minimumScoreThreshold
      else { continue }
      results.append(RecommendedEpisode(episode: episode, score: score))
    }
    results.sort { a, b in
      if a.score.value != b.score.value { return a.score.value > b.score.value }
      if a.episode.pubDate != b.episode.pubDate { return a.episode.pubDate > b.episode.pubDate }
      return a.episode.id > b.episode.id
    }
    let top = IdentifiedArrayOf<RecommendedEpisode>(uniqueElements: results.prefix(limit))

    Self.log.debug(
      "Returning \(top.count) recommendations from \(candidates.count) candidates"
    )
    return top
  }

  // MARK: - Scoring Pipeline

  private struct ScoringContext {
    let positiveCentroid: [Float]
    let negativeCentroid: [Float]?
    let podcastAffinities: [Podcast.ID: Float]
    let now: Date
  }

  // Returns nil if we can't meaningfully score: too few signals, no embeddings
  // yet, or no positive centroid. Both public methods short-circuit on nil.
  private func prepareScoringContext() async throws -> ScoringContext? {
    let signalEpisodes = try await repo.allSignalEpisodes()
    guard signalEpisodes.count >= Self.minimumDataThreshold else {
      Self.log.debug(
        """
        Not enough signal data (\(signalEpisodes.count)/\(Self.minimumDataThreshold)), \
        returning empty
        """
      )
      return nil
    }

    guard try await repo.hasEmbeddings() else {
      Self.log.debug("No embeddings computed yet, returning empty")
      return nil
    }

    let (positive, negative) = try await buildCentroids(signalEpisodes: signalEpisodes)
    guard let positiveCentroid = positive else {
      Self.log.debug("No positive centroid (no embeddings available), returning empty")
      return nil
    }

    return ScoringContext(
      positiveCentroid: positiveCentroid,
      negativeCentroid: negative,
      podcastAffinities: computePodcastAffinities(signalEpisodes: signalEpisodes),
      now: Date()
    )
  }

  private func scoreEpisodes(
    _ episodes: [Episode],
    context: ScoringContext
  ) async throws -> [Episode.ID: RecommendationScore] {
    let episodeIDs = episodes.map(\.id)
    let embeddings = try await repo.embeddings(for: episodeIDs)
    var scores = [Episode.ID: RecommendationScore](capacity: episodes.count)
    for episode in episodes {
      guard
        let score = scoreCandidate(
          embedding: embeddings[id: episode.id],
          podcastID: episode.podcastID,
          pubDate: episode.pubDate,
          positiveCentroid: context.positiveCentroid,
          negativeCentroid: context.negativeCentroid,
          podcastAffinities: context.podcastAffinities,
          now: context.now
        )
      else { continue }
      scores[episode.id] = score
    }
    return scores
  }

  // MARK: - Build Centroids

  private func buildCentroids(
    signalEpisodes: [SignalEpisode]
  ) async throws -> (positive: [Float]?, negative: [Float]?) {
    let episodeIDs: [Episode.ID] = signalEpisodes.map(\.id)
    let embeddingsByEpisode = try await repo.embeddings(for: episodeIDs)

    let now = Date()
    var positiveVectors = [(vector: [Float], weight: Float)](capacity: signalEpisodes.count)
    var negativeVectors = [(vector: [Float], weight: Float)](capacity: signalEpisodes.count)

    for signal in signalEpisodes {
      guard let cached = embeddingsByEpisode[id: signal.id] else { continue }
      let vector = cached.floatVector

      let signalDate: Date? =
        switch signal.kind {
        case .rating: signal.episode.ratingDate
        case .finished: signal.episode.finishDate
        }
      let decay = temporalDecay(from: signalDate, now: now)

      switch signal.kind {
      case .rating(.loved):
        positiveVectors.append((vector, Self.lovedWeight * decay))
      case .rating(.liked):
        positiveVectors.append((vector, Self.likedWeight * decay))
      case .rating(.disliked):
        negativeVectors.append((vector, decay))
      case .finished:
        positiveVectors.append((vector, Self.finishedWeight * decay))
      }
    }

    let positive = computeWeightedCentroid(positiveVectors)
    let negative = computeWeightedCentroid(negativeVectors)

    return (positive, negative)
  }

  // MARK: - Score Candidate

  private func scoreCandidate(
    embedding: EpisodeEmbedding?,
    podcastID: Podcast.ID,
    pubDate: Date,
    positiveCentroid: [Float]?,
    negativeCentroid: [Float]?,
    podcastAffinities: [Podcast.ID: Float],
    now: Date
  ) -> RecommendationScore? {
    var features: [(weight: Float, value: Float, reason: RecommendationReason)] = []

    // Content similarity (dual centroid)
    if let embedding,
      let positiveCentroid
    {
      let vector = embedding.floatVector
      var similarity = VectorMath.dotProduct(vector, positiveCentroid)
      if let negativeCentroid {
        similarity -= VectorMath.dotProduct(vector, negativeCentroid)
      }
      // Remap from [-2, 2] to [0, 1]
      let remapped = (similarity + 2.0) / 4.0
      features.append((Self.similarityWeight, remapped, .similarToLiked))
    }

    // Podcast affinity
    let affinity = podcastAffinities[podcastID] ?? 0
    // Remap from [-1, 1] to [0, 1]
    let remappedAffinity = (affinity + 1.0) / 2.0
    features.append((Self.podcastAffinityWeight, remappedAffinity, .podcastAffinity))

    // Freshness
    let freshness = freshnessScore(pubDate: pubDate, now: now)
    features.append((Self.freshnessWeight, freshness, .recentlyPublished))

    // Renormalize weights over available features
    let totalWeight = features.reduce(Float(0)) { $0 + $1.weight }
    guard totalWeight > 0 else { return nil }

    let score = features.reduce(Float(0)) { sum, feature in
      sum + (feature.weight / totalWeight) * feature.value
    }

    // A reason fires only when its feature is above its own neutral midpoint.
    // Each feature's value is normalized to [0, 1] with 0.5 = neutral, so this
    // surfaces only features that are actively positive for this episode — not
    // every feature that happened to fire.
    let reasons = features.filter { $0.value > 0.5 }.map(\.reason)

    return RecommendationScore(value: score, reasons: reasons)
  }

  // MARK: - Podcast Affinity

  private func computePodcastAffinities(signalEpisodes: [SignalEpisode]) -> [Podcast.ID: Float] {
    var podcastStats = [Podcast.ID: (positive: Float, negative: Float, total: Float)](
      capacity: signalEpisodes.count
    )

    for signal in signalEpisodes {
      let podcastID = signal.episode.podcastID
      var stats = podcastStats[podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1

      switch signal.kind {
      case .rating(.loved), .rating(.liked):
        stats.positive += 1
      case .rating(.disliked):
        stats.negative += Self.dislikedAffinityWeight
      case .finished:
        stats.positive += 0.5
      }

      podcastStats[podcastID] = stats
    }

    // Bayesian smoothed affinity: (positive - negative) / (total + prior).
    return podcastStats.mapValues { stats in
      (stats.positive - stats.negative) / (stats.total + Self.affinityPrior)
    }
  }

  // MARK: - Temporal Decay

  private func temporalDecay(from date: Date?, now: Date) -> Float {
    guard let date else { return 1.0 }
    let daysSince = now.timeIntervalSince(date) / 86400
    guard daysSince > 0 else { return 1.0 }
    // Half-life decay: weight = 0.5^(days / halfLife)
    return Float(pow(0.5, daysSince / Self.decayHalfLifeDays))
  }

  // MARK: - Freshness

  private func freshnessScore(pubDate: Date, now: Date) -> Float {
    let daysSince = now.timeIntervalSince(pubDate) / 86400
    guard daysSince > 0 else { return 1.0 }
    return Float(1.0 / (1.0 + daysSince / Self.freshnessMidpointDays))
  }

  // MARK: - Centroid Math

  private func computeWeightedCentroid(
    _ vectors: [(vector: [Float], weight: Float)]
  ) -> [Float]? {
    guard let first = vectors.first else { return nil }
    let dim = first.vector.count

    var sum = [Float](repeating: 0, count: dim)
    var totalWeight: Float = 0

    for (vector, weight) in vectors where vector.count == dim {
      for i in 0..<dim {
        sum[i] += vector[i] * weight
      }
      totalWeight += weight
    }

    guard totalWeight > 0 else { return nil }
    let centroid = sum.map { $0 / totalWeight }
    return VectorMath.normalize(centroid)
  }
}
