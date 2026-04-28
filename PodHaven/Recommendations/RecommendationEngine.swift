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
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.taskPriority) private var taskPriority

  private static let log = Log.as(LogSubsystem.Recommendations.engine)

  private static let minimumDataThreshold = 3
  private static let minimumScoreThreshold: Float = 0.1

  // Must sum to 1.0. Similarity dominates 4:1 so a single liked episode
  // doesn't drag in everything that podcast ever published. Freshness isn't
  // a summand — it's a multiplicative gate (see `scoreCandidate`).
  private static let similarityWeight: Float = 0.8
  private static let podcastAffinityWeight: Float = 0.2

  // Centroid weights
  private static let lovedWeight: Float = 1.0
  private static let likedWeight: Float = 0.6
  private static let partialWeight: Float = 0.4

  // Bayesian smoothing prior for podcast affinity
  private static let affinityPrior: Float = 2.0

  // Podcast affinity — dislikes contribute but at half the strength of likes.
  // One bad episode shouldn't tank an otherwise-loved show, but repeated
  // dislikes should still register as show-level aversion.
  private static let dislikedAffinityWeight: Float = 0.5

  // Temporal decay half-life in days
  private static let decayHalfLifeDays: Double = 180

  // MARK: - Cached Scoring Context

  private let cache = ThreadSafe<ScoringContext?>(nil)
  private let startOnce = Once()

  fileprivate init() {}

  // MARK: - Public API

  // Idempotent. Spawns the observation Task that keeps `cache` in sync with
  // the DB. AppLauncher calls this during foreground init; tests call it
  // after seeding their fixture. Public scoring methods do NOT auto-call
  // `start()` — they just read whatever the cache currently has and return
  // empty when it's nil. That keeps every recommendations() call
  // latency-free and pushes "is the cache hot?" to the lifecycle owner.
  func start() {
    startOnce.run {
      startObservingScoringContext()
    }
  }

  // Score an arbitrary set of episodes so a caller can sort a list by "how
  // recommended." Unlike `topRecommendations`, there's no candidate filter,
  // no minimum-score floor, and no limit — every requested episode that has
  // sufficient context gets a score. Callers already have the episodes, so
  // we return just the new info (score + reasons) keyed by ID. Returns
  // empty if `start()` hasn't yet hydrated the cache.
  func recommendations(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    guard !episodes.isEmpty else { return [:] }
    guard let context = cache() else { return [:] }
    return try await scoreEpisodes(episodes, context: context)
  }

  func topRecommendations(limit: Int = 10) async throws -> IdentifiedArrayOf<RecommendedEpisode> {
    Self.log.debug("Generating top recommendations (limit: \(limit))")
    // Direct Container.shared access because SharedState isn't Sendable and
    // @DynamicInjected requires a Sendable type. The property read is @MainActor
    // isolated in practice; onDeck is a Sendable value type so the copy is safe.
    let onDeckID = Container.shared.sharedState().onDeck?.id
    let candidates = try await repo.allCandidateEpisodes(excluding: onDeckID)
    let scores = try await recommendations(for: candidates)
    guard !scores.isEmpty else { return [] }

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

  // MARK: - ScoringContext

  // The output of one centroid+affinity build, reused across every
  // `recommendations(for:)` / `topRecommendations()` call until the
  // observation emits a new `ScoringContextInputs`.
  private struct ScoringContext: Sendable {
    let positiveCentroid: [Float]
    let negativeCentroid: [Float]?
    let podcastAffinities: [Podcast.ID: Float]
    let freshnessCadences: [Podcast.ID: FreshnessCadence]
  }

  private func startObservingScoringContext() {
    Task(priority: taskPriority(.utility)) {
      do {
        for try await inputs in observatory.scoringContextInputs() {
          guard !Task.isCancelled else { return }
          cache(Self.buildContext(from: inputs))
        }
      } catch {
        Self.log.caughtError("scoringContextInputs observation failed", error)
      }
    }

    // onDeck transitions cover session boundaries that the GRDB observation
    // can't see — partial-listen bitmaps and lastPlayedDate are excluded
    // from its tracked region. Each id change (load / change / clear)
    // triggers a one-shot rebuild against the latest DB snapshot.
    Task(priority: taskPriority(.utility)) {
      let sharedState = Container.shared.sharedState()
      var lastID: Episode.ID? = nil
      var sawFirst = false
      for await onDeck in sharedState.$onDeck.stream() {
        guard !Task.isCancelled else { return }
        let currentID = onDeck?.id
        guard sawFirst else {
          sawFirst = true
          lastID = currentID
          continue
        }
        guard currentID != lastID else { continue }
        lastID = currentID
        do {
          let inputs = try await repo.latestScoringContextInputs()
          cache(Self.buildContext(from: inputs))
        } catch {
          Self.log.caughtError("onDeck-triggered scoring rebuild failed", error)
        }
      }
    }
  }

  // MARK: - Build Context

  private static func buildContext(from inputs: ScoringContextInputs) -> ScoringContext? {
    let totalSignalCount = inputs.ratedSignals.count + inputs.partialSignals.count
    guard totalSignalCount >= minimumDataThreshold else {
      log.debug(
        """
        Not enough signal data (\(totalSignalCount)/\(minimumDataThreshold)), \
        cached context cleared
        """
      )
      return nil
    }

    guard inputs.hasAnyEmbeddings else {
      log.debug("No embeddings computed yet, cached context cleared")
      return nil
    }

    let (positive, negative) = buildCentroids(
      ratedSignals: inputs.ratedSignals,
      partialSignals: inputs.partialSignals,
      embeddings: inputs.signalEmbeddings
    )
    guard let positiveCentroid = positive else {
      log.debug("No positive centroid (no signal embeddings available), cached context cleared")
      return nil
    }

    return ScoringContext(
      positiveCentroid: positiveCentroid,
      negativeCentroid: negative,
      podcastAffinities: computePodcastAffinities(
        ratedSignals: inputs.ratedSignals,
        partialSignals: inputs.partialSignals
      ),
      freshnessCadences: inputs.freshnessCadences
    )
  }

  // MARK: - Score Episodes

  private func scoreEpisodes(
    _ episodes: [Episode],
    context: ScoringContext
  ) async throws -> [Episode.ID: RecommendationScore] {
    let episodeIDs = episodes.map(\.id)
    let embeddings = try await repo.embeddings(for: episodeIDs)
    let now = Date()
    var scores = [Episode.ID: RecommendationScore](capacity: episodes.count)
    for episode in episodes {
      scores[episode.id] = scoreCandidate(
        embedding: embeddings[id: episode.id],
        podcastID: episode.podcastID,
        pubDate: episode.pubDate,
        positiveCentroid: context.positiveCentroid,
        negativeCentroid: context.negativeCentroid,
        podcastAffinities: context.podcastAffinities,
        freshnessCadence: context.freshnessCadences[episode.podcastID] ?? FreshnessCadence.default,
        now: now
      )
    }
    return scores
  }

  // MARK: - Build Centroids

  private static func buildCentroids(
    ratedSignals: [SignalEpisode],
    partialSignals: [PartialSignal],
    embeddings: IdentifiedArray<Episode.ID, EpisodeEmbedding>
  ) -> (positive: [Float]?, negative: [Float]?) {
    let now = Date()
    let capacity = ratedSignals.count + partialSignals.count
    var positiveVectors = [(vector: [Float], weight: Float)](capacity: capacity)
    var negativeVectors = [(vector: [Float], weight: Float)](capacity: capacity)

    for signal in ratedSignals {
      guard let cached = embeddings[id: signal.id] else { continue }
      let vector = cached.floatVector
      let decay = temporalDecay(from: signal.ratingDate, now: now)

      switch signal.rating {
      case .loved:
        positiveVectors.append((vector, lovedWeight * decay))
      case .liked:
        positiveVectors.append((vector, likedWeight * decay))
      case .disliked:
        negativeVectors.append((vector, decay))
      }
    }

    for partial in partialSignals {
      guard let cached = embeddings[id: partial.id] else { continue }
      let weight =
        partialWeight * Float(partial.coverageRatio)
        * temporalDecay(from: partial.lastPlayedDate, now: now)
      positiveVectors.append((cached.floatVector, weight))
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
    freshnessCadence: FreshnessCadence,
    now: Date
  ) -> RecommendationScore {
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

    // Renormalize weights so a missing-embedding candidate (totalWeight 0.2)
    // still produces a comparable score. Guard catches misconfigured weights.
    let totalWeight = features.reduce(Float(0)) { $0 + $1.weight }
    guard totalWeight > 0 else {
      Assert.fatal("scoreCandidate: totalWeight is zero — scoring weights misconfigured")
    }

    let baseScore = features.reduce(Float(0)) { sum, feature in
      sum + (feature.weight / totalWeight) * feature.value
    }

    // Multiplicative gate, not a summand: a year-old daily-news episode
    // drops to ≈0 instead of being capped by a fixed-weight summand.
    let freshness = FreshnessSignal.compute(
      pubDate: pubDate,
      cadence: freshnessCadence,
      now: now
    )
    let score = baseScore * freshness.multiplier

    var reasons = features.filter { $0.value > 0.5 }.map(\.reason)
    if freshness.inPlateau {
      reasons.append(.recentlyPublished)
    }

    return RecommendationScore(value: score, reasons: reasons)
  }

  // MARK: - Podcast Affinity

  private static func computePodcastAffinities(
    ratedSignals: [SignalEpisode],
    partialSignals: [PartialSignal]
  ) -> [Podcast.ID: Float] {
    let capacity = ratedSignals.count + partialSignals.count
    var podcastStats = [Podcast.ID: (positive: Float, negative: Float, total: Float)](
      capacity: capacity
    )

    for signal in ratedSignals {
      var stats = podcastStats[signal.podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1

      switch signal.rating {
      case .loved, .liked:
        stats.positive += 1
      case .disliked:
        stats.negative += dislikedAffinityWeight
      }

      podcastStats[signal.podcastID] = stats
    }

    for partial in partialSignals {
      var stats = podcastStats[partial.podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1
      stats.positive += Float(partial.coverageRatio)
      podcastStats[partial.podcastID] = stats
    }

    // Bayesian smoothed affinity: (positive - negative) / (total + prior).
    return podcastStats.mapValues { stats in
      (stats.positive - stats.negative) / (stats.total + affinityPrior)
    }
  }

  // MARK: - Temporal Decay

  private static func temporalDecay(from date: Date?, now: Date) -> Float {
    guard let date else { return 1.0 }
    let daysSince = now.timeIntervalSince(date) / 86400
    guard daysSince > 0 else { return 1.0 }
    // Half-life decay: weight = 0.5^(days / halfLife)
    return Float(pow(0.5, daysSince / decayHalfLifeDays))
  }

  // MARK: - Centroid Math

  private static func computeWeightedCentroid(
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
