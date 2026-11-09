// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Embeddings from a revision other than the current one leave the engine
// without a whitening transform, so it scores raw vectors whose dimensions
// may differ from the centroid's.
@Suite("Recommendation scoring with mixed embedding dimensions", .container)
class MixedDimensionScoringTests {
  @Test("a candidate whose dimension differs from the centroid scores neutral similarity")
  func mismatchedCandidateScoresNeutralSimilarity() async throws {
    let embeddable = ScriptedEmbeddable(revision: 2) { text in
      text.contains("Wide") ? [1, 0, 0, 0] : [1, 0, 0]
    }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Wide",
      podcastDescription: "Wide",
      episodeDescriptions: ["Wide"]
    )
    try await RecommendationHelpers.embedEpisodes(candidates, embeddable: embeddable)

    let candidate = try #require(candidates.first)
    let scores = try await RecommendationHelpers.startAndWaitForScores(for: [candidate])
    let score = try #require(scores[candidate.id])
    #expect(!score.reasons.contains(.similarToLiked))
  }

  @Test("signals whose dimension differs from the centroid do not move it")
  func mismatchedSignalsDoNotMoveCentroid() async throws {
    let embeddable = ScriptedEmbeddable(revision: 2) { text in
      if text.contains("Short") { return [0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      return [0, 1, 0]
    }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal"],
      ratings: [.loved]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let (_, shortSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Short",
      podcastDescription: "Short",
      episodeDescriptions: ["Short", "Short", "Short"],
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(shortSignals, embeddable: embeddable)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target"]
    )
    try await RecommendationHelpers.embedEpisodes(candidates, embeddable: embeddable)

    let candidate = try #require(candidates.first)
    let scores = try await RecommendationHelpers.startAndWaitForScores(for: [candidate])
    let score = try #require(scores[candidate.id])
    #expect(!score.reasons.contains(.similarToLiked))
  }
}
