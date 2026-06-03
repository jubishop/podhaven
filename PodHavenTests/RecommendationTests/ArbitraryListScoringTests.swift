// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine arbitrary-list scoring tests", .container)
class ArbitraryListScoringTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.queue) private var queue

  @Test("recommendations(for:) scores every requested episode that has an embedding")
  func recommendationsForArbitraryListWithEmbeddings() async throws {
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
    let top = try await engine.topRecommendations(limit: 10)
    let topIDs = Set(top)
    for episode in filtered {
      #expect(!topIDs.contains(episode.id))
    }
  }

  @Test("recommendations(for:) with empty input returns empty without touching the cache")
  func recommendationsForEmptyInput() async throws {
    let map = try await engine.recommendations(for: [] as [Episode])
    #expect(map.isEmpty)
  }

  // Issue #411 regression: the UpNext sort scores already-queued (non-candidate)
  // episodes via `unscaledRecommendationScores(forEpisodeIDs:)`. Their raw scores
  // can exceed the display anchor (calibrated only over the candidate pool), and
  // the display rescale clamps everything above the anchor to 1.0 — collapsing
  // the ordering of the highest-scoring queued episodes into a tie. The sort path
  // must return raw scores so distinct top scores stay distinct.
  @Test("unscaledRecommendationScores(forEpisodeIDs:) preserves ordering above the anchor")
  func unscaledRecommendationScoresPreservesOrderAboveAnchor() async throws {
    // Pure podcast-affinity scoring: each episode's raw score is its podcast's
    // remapped affinity, with future pubDates pinning freshness to 1.0.
    Container.shared.userSettings().$podcastAffinityWeight.new(1.0)
    let future: (Int) -> TimeInterval = { i in TimeInterval((i + 1) * 86400) }

    // Anchor podcast: 3 loved → affinity 0.6 → candidates score 0.8, the pool max.
    let (anchorPodcast, anchorSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Anchor",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(anchorSignals)
    let anchorCandidates = try await RecommendationHelpers.addEpisodes(
      to: anchorPodcast,
      count: 2,
      pubDateOffset: future
    )
    try await RecommendationHelpers.embedEpisodes(anchorCandidates)

    // Higher-affinity podcast → queued episode A scores above the anchor.
    let (podcastA, signalsA) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 5,
      podcastTitle: "High A",
      ratings: Array(repeating: .loved, count: 5)
    )
    try await RecommendationHelpers.embedEpisodes(signalsA)
    let queuedA = try await RecommendationHelpers.addEpisodes(
      to: podcastA,
      count: 1,
      pubDateOffset: future
    )
    try await RecommendationHelpers.embedEpisodes(queuedA)

    // Slightly lower affinity (still above the anchor) → queued episode B.
    let (podcastB, signalsB) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 4,
      podcastTitle: "High B",
      ratings: Array(repeating: .loved, count: 4)
    )
    try await RecommendationHelpers.embedEpisodes(signalsB)
    let queuedB = try await RecommendationHelpers.addEpisodes(
      to: podcastB,
      count: 1,
      pubDateOffset: future
    )
    try await RecommendationHelpers.embedEpisodes(queuedB)

    let episodeA = try #require(queuedA.first)
    let episodeB = try #require(queuedB.first)

    // Queue A and B so they drop out of the candidate pool that sets the anchor.
    try await queue.append([episodeA.id, episodeB.id])

    _ = try await RecommendationHelpers.startAndWaitForScores(for: [episodeA, episodeB])
    // Calibrate the display anchor over the candidate pool (A and B excluded).
    _ = try await engine.topRecommendations(limit: 100)

    let scores = try await engine.unscaledRecommendationScores(
      forEpisodeIDs: [episodeA.id, episodeB.id]
    )
    let scoreA = try #require(scores[episodeA.id])
    let scoreB = try #require(scores[episodeB.id])

    // A's affinity is strictly higher than B's, and both exceed the anchor. On
    // the display-rescaled path both clamp to 1.0 and tie; raw scores stay
    // ordered and below 1.0.
    #expect(scoreA > scoreB)
    #expect(scoreA < 1.0)
  }
}
