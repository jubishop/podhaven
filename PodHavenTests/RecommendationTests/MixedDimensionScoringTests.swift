// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Embeddings whose dimension differs from the rest of the current revision's
// corpus must neither score as similar nor move the centroid. Focused mode
// keeps whitening to mean-centering, so the centroid keeps a direction.
@Suite("Recommendation scoring with mixed embedding dimensions", .container)
class MixedDimensionScoringTests {
  @Test("a candidate whose dimension differs from the centroid scores neutral similarity")
  func mismatchedCandidateScoresNeutralSimilarity() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Wide") { return [1, 0, 0, 0] }
      if text.contains("Anchor") { return [0, 1, 0] }
      return [1, 0, 0]
    }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // Moves the corpus mean off the signals, so centering leaves them a
    // direction that a wide candidate read as its first three components
    // would match.
    let (_, anchors) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Anchor",
      podcastDescription: "Anchor",
      episodeDescriptions: ["Anchor"]
    )
    try await RecommendationHelpers.embedEpisodes(anchors, embeddable: embeddable)

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
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let embeddable = ScriptedEmbeddable { text in
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
