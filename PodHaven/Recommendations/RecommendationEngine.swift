// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging

// MARK: - Types

struct RecommendedEpisode: Sendable {
  let episode: Episode
  let score: Float
  let reasons: [RecommendationReason]
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
  // sufficient context gets a score. Callers typically already have full
  // `Episode` values, so we take those directly to skip a pointless round-trip
  // through the DB.
  func recommendations(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendedEpisode] {
    guard !episodes.isEmpty else { return [:] }
    guard let context = try await prepareScoringContext() else { return [:] }
    let scored = try await scoreEpisodes(episodes, context: context)
    return Dictionary(uniqueKeysWithValues: scored.map { ($0.episode.id, $0) })
  }

  func topRecommendations(limit: Int = 10) async throws -> [RecommendedEpisode] {
    Self.log.debug("Generating top recommendations (limit: \(limit))")
    let candidates = try await fetchCandidates()
    let scored = try await recommendations(for: candidates)

    // Sort with deterministic tie-breaking
    var results = Array(scored.values)
    results.sort { a, b in
      if a.score != b.score { return a.score > b.score }
      if a.episode.pubDate != b.episode.pubDate { return a.episode.pubDate > b.episode.pubDate }
      return a.episode.id > b.episode.id
    }

    // Apply confidence floor and limit
    results = results.filter { $0.score >= Self.minimumScoreThreshold }
    let topResults = Array(results.prefix(limit))

    Self.log.debug(
      "Returning \(topResults.count) recommendations from \(candidates.count) candidates"
    )
    return topResults
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
  ) async throws -> [RecommendedEpisode] {
    let episodeIDs = episodes.map(\.id)
    let embeddings = try await repo.embeddings(for: episodeIDs)
    return episodes.compactMap { episode in
      scoreCandidate(
        episode: episode,
        embedding: embeddings[id: episode.id],
        positiveCentroid: context.positiveCentroid,
        negativeCentroid: context.negativeCentroid,
        podcastAffinities: context.podcastAffinities,
        now: context.now
      )
    }
  }

  // MARK: - Build Centroids

  private func buildCentroids(
    signalEpisodes: [SignalEpisode]
  ) async throws -> (positive: [Float]?, negative: [Float]?) {
    let episodeIDs: [Episode.ID] = signalEpisodes.map(\.id)
    let embeddingsByEpisode = try await repo.embeddings(for: episodeIDs)

    let now = Date()
    var positiveVectors: [(vector: [Float], weight: Float)] = []
    var negativeVectors: [(vector: [Float], weight: Float)] = []

    for signal in signalEpisodes {
      guard let cached = embeddingsByEpisode[id: signal.id] else { continue }
      let vector = cached.floatVector

      switch signal.kind {
      case .rating(.loved):
        let decay = temporalDecay(from: signal.episode.ratingDate, now: now)
        positiveVectors.append((vector, Self.lovedWeight * decay))
      case .rating(.liked):
        let decay = temporalDecay(from: signal.episode.ratingDate, now: now)
        positiveVectors.append((vector, Self.likedWeight * decay))
      case .rating(.disliked):
        let decay = temporalDecay(from: signal.episode.ratingDate, now: now)
        negativeVectors.append((vector, decay))
      case .finished:
        let decay = temporalDecay(from: signal.episode.finishDate, now: now)
        positiveVectors.append((vector, Self.finishedWeight * decay))
      }
    }

    let positive = computeWeightedCentroid(positiveVectors)
    let negative = computeWeightedCentroid(negativeVectors)

    return (positive, negative)
  }

  // MARK: - Score Candidate

  private func scoreCandidate(
    episode: Episode,
    embedding: EpisodeEmbedding?,
    positiveCentroid: [Float]?,
    negativeCentroid: [Float]?,
    podcastAffinities: [Podcast.ID: Float],
    now: Date
  ) -> RecommendedEpisode? {
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
    let affinity = podcastAffinities[episode.podcastID] ?? 0
    // Remap from [-1, 1] to [0, 1]
    let remappedAffinity = (affinity + 1.0) / 2.0
    features.append((Self.podcastAffinityWeight, remappedAffinity, .podcastAffinity))

    // Freshness
    let freshness = freshnessScore(pubDate: episode.pubDate, now: now)
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

    return RecommendedEpisode(episode: episode, score: score, reasons: reasons)
  }

  // MARK: - Fetch Candidates

  private func fetchCandidates() async throws -> [Episode] {
    let onDeckID = Container.shared.sharedState().onDeck?.id
    let excluded = [onDeckID].compactMap { $0 }
    return try await repo.allCandidateEpisodes(excluding: excluded)
  }

  // MARK: - Podcast Affinity

  private func computePodcastAffinities(signalEpisodes: [SignalEpisode]) -> [Podcast.ID: Float] {
    var podcastStats: [Podcast.ID: (positive: Float, negative: Float, total: Float)] = [:]

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
