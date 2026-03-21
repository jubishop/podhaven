// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
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
  case tagAffinity
  case recentlyPublished
  case durationMatch
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
  @DynamicInjected(\.embeddingService) private var embeddingService

  private static let log = Log.as(LogSubsystem.Recommendations.engine)

  private static let minimumDataThreshold = 3
  private static let minimumScoreThreshold: Float = 0.1

  // Scoring weights (must sum to 1.0)
  private static let similarityWeight: Float = 0.40
  private static let podcastAffinityWeight: Float = 0.20
  private static let tagAffinityWeight: Float = 0.15
  private static let freshnessWeight: Float = 0.15
  private static let durationFitWeight: Float = 0.10

  // Centroid weights
  private static let lovedWeight: Float = 1.0
  private static let likedWeight: Float = 0.5
  private static let finishedWeight: Float = 0.2

  // Bayesian smoothing prior for podcast affinity
  private static let affinityPrior: Float = 2.0

  // Temporal decay half-life in days
  private static let decayHalfLifeDays: Double = 180

  // MARK: - Get Recommendations

  func getRecommendations(limit: Int = 10) async throws -> [RecommendedEpisode] {
    Self.log.debug("Generating recommendations (limit: \(limit))")

    let signalEpisodes = try await fetchSignalEpisodes()
    guard signalEpisodes.count >= Self.minimumDataThreshold else {
      Self.log.debug(
        """
        Not enough signal data (\(signalEpisodes.count)/\(Self.minimumDataThreshold)), \
        returning empty
        """
      )
      return []
    }

    guard embeddingService.resolveEmbedding() != nil else {
      Self.log.debug("Contextual embedding assets not available yet, returning empty")
      return []
    }

    // Build centroids
    let (positiveCentroid, negativeCentroid) = try await buildCentroids(
      signalEpisodes: signalEpisodes
    )

    guard positiveCentroid != nil else {
      Self.log.debug("No positive centroid (no embeddings available), returning empty")
      return []
    }

    // Fetch candidates
    let candidates = try await fetchCandidates()
    guard !candidates.isEmpty else {
      Self.log.debug("No candidate episodes found")
      return []
    }

    // Compute scoring context
    let podcastAffinities = computePodcastAffinities(signalEpisodes: signalEpisodes)
    let tagAffinities = try await computeTagAffinities(signalEpisodes: signalEpisodes)
    let medianDuration = computeMedianDuration(signalEpisodes: signalEpisodes)
    let now = Date()

    // Score candidates
    let candidateIDs: [Episode.ID] = candidates.map { $0.id }
    let candidateEmbeddings = try await repo.embeddings(for: candidateIDs)
    let embeddingsByEpisode: [Episode.ID: EpisodeEmbedding] = Dictionary(
      candidateEmbeddings.map { ($0.episodeId, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    var results: [RecommendedEpisode] = candidates.compactMap { episode in
      scoreCandidate(
        episode: episode,
        embedding: embeddingsByEpisode[episode.id],
        positiveCentroid: positiveCentroid,
        negativeCentroid: negativeCentroid,
        podcastAffinities: podcastAffinities,
        tagAffinities: tagAffinities,
        medianDuration: medianDuration,
        now: now
      )
    }

    // Sort with deterministic tie-breaking
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

  // MARK: - Build Centroids

  private func buildCentroids(
    signalEpisodes: [Episode]
  ) async throws -> (positive: [Float]?, negative: [Float]?) {
    let episodeIDs: [Episode.ID] = signalEpisodes.map { $0.id }
    let embeddings = try await repo.embeddings(for: episodeIDs)
    let embeddingsByEpisode: [Episode.ID: EpisodeEmbedding] = Dictionary(
      embeddings.map { ($0.episodeId, $0) },
      uniquingKeysWith: { first, _ in first }
    )

    let now = Date()
    var positiveVectors: [(vector: [Float], weight: Float)] = []
    var negativeVectors: [(vector: [Float], weight: Float)] = []

    for episode in signalEpisodes {
      guard let cached = embeddingsByEpisode[episode.id] else { continue }
      let vector = cached.floatVector

      if let rating = episode.rating {
        let decay = temporalDecay(from: episode.ratingDate, now: now)
        switch rating {
        case .loved:
          positiveVectors.append((vector, Self.lovedWeight * decay))
        case .liked:
          positiveVectors.append((vector, Self.likedWeight * decay))
        case .disliked:
          negativeVectors.append((vector, decay))
        }
      } else if episode.finished {
        let decay = temporalDecay(from: episode.finishDate, now: now)
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
    tagAffinities: [Podcast.ID: Float],
    medianDuration: Double?,
    now: Date
  ) -> RecommendedEpisode? {
    var features: [(weight: Float, value: Float, reason: RecommendationReason)] = []

    // Content similarity (dual centroid)
    if let embedding,
      let positiveCentroid
    {
      let vector = embedding.floatVector
      var similarity = embeddingService.dotProduct(vector, positiveCentroid)
      if let negativeCentroid {
        similarity -= embeddingService.dotProduct(vector, negativeCentroid)
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

    // Tag affinity
    let tagScore = tagAffinities[episode.podcastID] ?? 0
    if tagScore > 0 {
      features.append((Self.tagAffinityWeight, tagScore, .tagAffinity))
    }

    // Freshness
    let freshness = freshnessScore(pubDate: episode.pubDate, now: now)
    features.append((Self.freshnessWeight, freshness, .recentlyPublished))

    // Duration fit
    if let medianDuration, medianDuration > 0 {
      let episodeDuration = episode.duration.seconds
      if episodeDuration > 0 {
        let ratio = min(episodeDuration, medianDuration) / max(episodeDuration, medianDuration)
        features.append((Self.durationFitWeight, Float(ratio), .durationMatch))
      }
    }

    // Renormalize weights over available features
    let totalWeight = features.reduce(Float(0)) { $0 + $1.weight }
    guard totalWeight > 0 else { return nil }

    let score = features.reduce(Float(0)) { sum, feature in
      sum + (feature.weight / totalWeight) * feature.value
    }

    let significantReasons =
      features
      .filter { ($0.weight / totalWeight) * $0.value > 0.05 }
      .map(\.reason)

    return RecommendedEpisode(
      episode: episode,
      score: score,
      reasons: significantReasons.isEmpty ? [.similarToLiked] : significantReasons
    )
  }

  // MARK: - Fetch Signal Episodes

  private func fetchSignalEpisodes() async throws -> [Episode] {
    try await repo.allSignalEpisodes()
  }

  // MARK: - Fetch Candidates

  private func fetchCandidates() async throws -> [Episode] {
    let onDeckID = Container.shared.sharedState().onDeck?.id
    return try await repo.allCandidateEpisodes(excludingOnDeckID: onDeckID)
  }

  // MARK: - Podcast Affinity

  private func computePodcastAffinities(signalEpisodes: [Episode]) -> [Podcast.ID: Float] {
    var podcastStats: [Podcast.ID: (positive: Float, negative: Float, total: Float)] = [:]

    for episode in signalEpisodes {
      let podcastID = episode.podcastID
      var stats = podcastStats[podcastID] ?? (positive: 0, negative: 0, total: 0)
      stats.total += 1

      if let rating = episode.rating {
        switch rating {
        case .loved, .liked:
          stats.positive += 1
        case .disliked:
          stats.negative += 1
        }
      } else if episode.finished {
        stats.positive += 0.5
      }

      podcastStats[podcastID] = stats
    }

    // Bayesian smoothed affinity: (positive - negative) / (total + prior)
    return podcastStats.mapValues { stats in
      (stats.positive - stats.negative) / (stats.total + Self.affinityPrior)
    }
  }

  // MARK: - Tag Affinity

  private func computeTagAffinities(signalEpisodes: [Episode]) async throws -> [Podcast.ID: Float] {
    let positiveEpisodes = signalEpisodes.filter { episode in
      if let rating = episode.rating {
        return rating == .loved || rating == .liked
      }
      return false
    }

    guard !positiveEpisodes.isEmpty else { return [:] }

    // Get tags from positively-rated episodes' podcasts
    let positivePodcastIDs = Set(positiveEpisodes.map(\.podcastID))

    let allTags = try await repo.allPodcastTags()
    var allPodcastTags: [Podcast.ID: Set<Tag.ID>] = [:]
    for tag in allTags {
      allPodcastTags[tag.podcastId, default: Set()].insert(tag.tagId)
    }

    let likedTags = positivePodcastIDs.reduce(into: Set<Tag.ID>()) { result, podcastID in
      if let tags = allPodcastTags[podcastID] {
        result.formUnion(tags)
      }
    }
    guard !likedTags.isEmpty else { return [:] }

    return allPodcastTags.mapValues { podcastTags in
      let overlap = podcastTags.intersection(likedTags).count
      guard !likedTags.isEmpty else { return 0 }
      return Float(overlap) / Float(likedTags.count)
    }
  }

  // MARK: - Duration

  private func computeMedianDuration(signalEpisodes: [Episode]) -> Double? {
    let durations =
      signalEpisodes
      .filter { episode in
        if let rating = episode.rating {
          return rating == .loved || rating == .liked
        }
        return episode.finished
      }
      .map { $0.duration.seconds }
      .filter { $0 > 0 }
      .sorted()

    guard !durations.isEmpty else { return nil }
    let mid = durations.count / 2
    if durations.count.isMultiple(of: 2) {
      return (durations[mid - 1] + durations[mid]) / 2
    }
    return durations[mid]
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
    // Sigmoid-like decay: episodes from the last week score ~1.0, older ones decay
    return Float(1.0 / (1.0 + daysSince / 30.0))
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
    return embeddingService.normalize(centroid)
  }
}
