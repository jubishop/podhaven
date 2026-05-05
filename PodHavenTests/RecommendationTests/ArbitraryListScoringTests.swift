// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine arbitrary-list scoring tests", .container)
class ArbitraryListScoringTests {
  @DynamicInjected(\.recommendationEngine) private var engine

  @Test("recommendations(for:) scores every requested episode")
  func recommendationsForArbitraryList() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 4,
      podcastTitle: "Arbitrary"
    )
    try await RecommendationHelpers.embedEpisodes(episodes)

    let map = try await RecommendationHelpers.startAndWaitForScores(for: episodes)
    #expect(map.count == episodes.count)
    for episode in episodes {
      #expect(map[episode.id] != nil)
    }
  }

  @Test("recommendations(for:) returns empty when signal threshold isn't met")
  func recommendationsForArbitraryListBelowThreshold() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Signal",
      ratings: [.loved, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Arbitrary"
    )
    try await RecommendationHelpers.embedEpisodes(episodes)

    engine.start()
    let map = try await engine.recommendations(for: episodes)
    #expect(map.isEmpty)
  }

  @Test("recommendations(for:) scores rated and finished episodes the top API skips")
  func recommendationsForArbitraryListIncludesFilteredEpisodes() async throws {
    // Enough positive signals from a separate podcast to satisfy the threshold.
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Mixed bag: a disliked episode and a finished episode — both would be
    // excluded by `topRecommendations` via the candidate filter.
    let (_, filtered) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Filtered",
      ratings: [.disliked, nil],
      finished: [false, true]
    )
    try await RecommendationHelpers.embedEpisodes(filtered)

    let map = try await RecommendationHelpers.startAndWaitForScores(for: filtered)
    #expect(map.count == filtered.count)
    for episode in filtered {
      #expect(map[episode.id] != nil)
    }

    // Sanity-check: the same episodes are absent from the top API.
    let top = try await engine.topRecommendations()
    let topIDs = Set(top.map(\.id))
    for episode in filtered {
      #expect(!topIDs.contains(episode.id))
    }
  }

  @Test("recommendations(for:) with empty input returns empty without touching the cache")
  func recommendationsForEmptyInput() async throws {
    let map = try await engine.recommendations(for: [])
    #expect(map.isEmpty)
  }
}
