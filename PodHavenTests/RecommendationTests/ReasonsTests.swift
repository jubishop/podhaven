// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine reasons tests", .container)
class ReasonsTests {
  @Test("recommendations include reasons")
  func recommendationsHaveReasons() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recommendations = try await RecommendationHelpers.startAndWaitForRecs()
    for rec in recommendations {
      #expect(!rec.score.reasons.isEmpty)
    }
  }

  @Test("year-old episodes don't include recentlyPublished reason")
  func oldEpisodesExcludeFreshnessReason() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Default cadence is weekly (7d plateau + 7d half-life). At 365d the
    // episode is far past the plateau, so `.recentlyPublished` (gated by
    // `freshness.inPlateau`) should not fire. Use the unfiltered scoring API
    // since the multiplier (~0.019) drops the gated score below the top
    // API's confidence floor.
    let (_, old) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Archive",
      pubDateOffset: { _ in TimeInterval(-365 * 86400) }
    )
    try await RecommendationHelpers.embedEpisodes(old)

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: old)
    let oldEpisode = try #require(old.first)
    let oldScore = try #require(scores[oldEpisode.id])
    #expect(!oldScore.reasons.contains(.recentlyPublished))
  }

  @Test("candidates from an unknown podcast don't include podcastAffinity reason")
  func unknownPodcastExcludesAffinityReason() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Candidates live in a podcast with zero positive signals — affinity
    // settles at the neutral 0.5 prior, which must not clear the reason filter.
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Unknown"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    for rec in recs where candidates.map(\.id).contains(rec.id) {
      #expect(!rec.score.reasons.contains(.podcastAffinity))
    }
  }

  @Test("semantically opposite candidates don't include similarToLiked reason")
  func oppositeCandidatesExcludeSimilarityReason() async throws {
    // Exploratory mode strips three PCs, which on 3-dim vectors collapses every
    // residual to zero. Pin to focused (mean-only) so the engineered opposition
    // survives whitening.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Loved") { return [1, 0, 0] }
      if text.contains("Opposite") { return [-1, 0, 0] }
      return [0, 0, 1]  // neutral filler for podcast descriptions etc.
    }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Loved Desc 0", "Loved Desc 1", "Loved Desc 2"],
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let (_, opposites) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Opposite Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Opposite Desc 0", "Opposite Desc 1"]
    )
    try await RecommendationHelpers.embedEpisodes(opposites, embeddable: embeddable)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    let oppositeIDs = Set(opposites.map(\.id))
    let oppositeRecs = recs.filter { oppositeIDs.contains($0.id) }
    #expect(!oppositeRecs.isEmpty)
    for rec in oppositeRecs {
      #expect(!rec.score.reasons.contains(.similarToLiked))
    }
  }

  @Test("candidates from a loved podcast include podcastAffinity reason")
  func lovedPodcastIncludesAffinityReason() async throws {
    // Three loved episodes on the same podcast drive affinity above neutral.
    let (lovedPodcast, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Unrated episodes on the SAME podcast are candidates that should carry
    // the affinity reason.
    let candidates = try await RecommendationHelpers.addEpisodes(to: lovedPodcast, count: 2)
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    let candidateIDs = Set(candidates.map(\.id))
    let candidateRecs = recs.filter { candidateIDs.contains($0.id) }
    #expect(!candidateRecs.isEmpty)
    for rec in candidateRecs {
      #expect(rec.score.reasons.contains(.podcastAffinity))
    }
  }
}
