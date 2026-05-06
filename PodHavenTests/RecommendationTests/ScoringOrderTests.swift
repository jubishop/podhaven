// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine scoring order tests", .container)
class ScoringOrderTests {
  @DynamicInjected(\.recommendationEngine) private var engine

  @Test("returns recommendations when threshold is met")
  func basicRecommendations() async throws {
    // Create rated episodes (signal)
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal Podcast",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    // Create candidate episodes (unrated, unfinished, unqueued)
    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate Podcast"
    )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes)

    let recommendations = try await RecommendationHelpers.startAndWaitForRecs()
    #expect(!recommendations.isEmpty)
    #expect(recommendations.count <= 10)

    // Verify deterministic ordering (scores should be descending)
    for i in 0..<(recommendations.count - 1) {
      #expect(recommendations[i].score.value >= recommendations[i + 1].score.value)
    }
  }

  @Test("breaks score ties by newer pubDate first")
  func tieBreakByPubDate() async throws {
    // Deterministic embeddings so similarity is identical for both candidates.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // Two candidates on the same podcast, same embedding. pubDates placed in
    // the future so freshnessScore short-circuits to 1.0 exactly for both
    // (daysSince <= 0 guard) — that's the only way to get bit-exact freshness
    // equality across two distinct pubDates. Same podcast → identical affinity.
    // Same embedding → identical similarity. Score tie by construction.
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      pubDateOffset: { i in TimeInterval((i == 0 ? 2 : 1) * 86400) }
    )
    try await RecommendationHelpers.embedEpisodes(candidates, embeddable: embeddable)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    let candidateIDs = Set(candidates.map(\.id))
    let candidateRecs = recs.filter { candidateIDs.contains($0.id) }
    #expect(candidateRecs.count == 2)
    let first = try #require(candidateRecs.first)
    let second = try #require(candidateRecs.last)
    #expect(first.score.value == second.score.value)

    // Look up pubDates from the source candidates since the engine no longer
    // echoes hydrated episodes back; ranking publishes IDs + scores only.
    let firstEpisode = try #require(candidates.first { $0.id == first.id })
    let secondEpisode = try #require(candidates.first { $0.id == second.id })
    #expect(firstEpisode.pubDate > secondEpisode.pubDate)
  }

  @Test("unembedded candidate doesn't outscore an embedded peer on the same podcast")
  func unembeddedCandidateDoesNotOutscoreEmbedded() async throws {
    // Embedded candidate's description tilts off the centroid axis just
    // enough that its similarity barely clears 0.5; under the old behavior
    // the unembedded sibling's pure-affinity score would outrank it.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Embedded Candidate") { return [0, 1, 0] }
      return [1, 0, 0]
    }

    let (lovedPodcast, signals) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 3,
        podcastTitle: "Loved",
        podcastDescription: "Loved",
        episodeDescriptions: ["Loved 0", "Loved 1", "Loved 2"],
        ratings: [.loved, .loved, .loved]
      )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // Same podcast → identical affinity; future pubDates → freshness 1.0,
    // so the only thing left to drive score difference is the embedding.
    let candidates = try await RecommendationHelpers.addEpisodes(
      to: lovedPodcast,
      count: 2,
      episodeDescriptions: ["Embedded Candidate", "Unembedded Candidate"],
      pubDateOffset: { i in TimeInterval((i == 0 ? 2 : 1) * 86400) }
    )
    let embeddedCandidate = try #require(candidates.first)
    let unembeddedCandidate = try #require(candidates.last)
    try await RecommendationHelpers.embedEpisodes(
      [embeddedCandidate],
      embeddable: embeddable
    )

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: candidates)
    let embeddedScore = try #require(scores[embeddedCandidate.id]).value
    let unembeddedScore = try #require(scores[unembeddedCandidate.id]).value
    #expect(embeddedScore > unembeddedScore)
  }

  @Test("honors custom limit by truncating results")
  func customLimit() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 5,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    engine.start()
    let engine = self.engine
    let limited = try await RecommendationHelpers.waitAdvancing {
      let recs = try await engine.topRecommendations(limit: 3)
      return recs.count == 3 ? recs : nil
    }
    #expect(limited.count == 3)
  }
}
