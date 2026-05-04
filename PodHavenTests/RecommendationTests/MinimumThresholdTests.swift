// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine minimum threshold tests", .container)
class MinimumThresholdTests {
  @DynamicInjected(\.recommendationEngine) private var engine

  @Test("returns empty when fewer than 3 signal episodes")
  func minimumThreshold() async throws {
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      ratings: [.loved, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(episodes)

    engine.start()
    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  @Test("handles all-disliked history gracefully")
  func allDisliked() async throws {
    _ = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Disliked",
      ratings: [.disliked, .disliked, .disliked]
    )

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    // Should return empty since there's no positive centroid
    engine.start()
    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  @Test("returns empty when signals exist but none have embeddings yet")
  func signalsWithoutEmbeddings() async throws {
    // 3 rated signals but no embeddings yet — transient state during initial
    // embedding-pipeline warmup. embeddingCount is non-zero (from candidates)
    // so the early hasAnyEmbeddings gate passes, but buildCentroids returns
    // nil because no signal embedding is available to seed the positive
    // centroid.
    _ = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    engine.start()
    let recs = try await engine.topRecommendations()
    #expect(recs.isEmpty)
  }
}
