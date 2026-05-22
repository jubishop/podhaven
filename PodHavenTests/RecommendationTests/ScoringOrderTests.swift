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

    let ranked = try await RecommendationHelpers.startAndWaitForRecs()
    #expect(!ranked.isEmpty)
    #expect(ranked.count <= 10)

    // Scores should descend. The ranking carries IDs only, so read scores
    // back through the per-candidate API — `rescaledForDisplay` is monotonic,
    // so its order matches how `topRecommendations` ranked.
    let scores = try await engine.recommendations(for: candidateEpisodes)
    for i in 0..<(ranked.count - 1) {
      let current = try #require(scores[ranked[i]]?.value)
      let next = try #require(scores[ranked[i + 1]]?.value)
      #expect(current >= next)
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
    let candidateRecs = recs.filter { candidateIDs.contains($0) }
    #expect(candidateRecs.count == 2)
    let first = try #require(candidateRecs.first)
    let second = try #require(candidateRecs.last)

    // The ranking carries IDs only; read the scores back to confirm the tie.
    let scores = try await engine.recommendations(for: candidates)
    let firstScore = try #require(scores[first]?.value)
    let secondScore = try #require(scores[second]?.value)
    #expect(firstScore == secondScore)

    let firstEpisode = try #require(candidates.first { $0.id == first })
    let secondEpisode = try #require(candidates.first { $0.id == second })
    #expect(firstEpisode.pubDate > secondEpisode.pubDate)
  }

  @Test("unembedded candidate is not scored at all (issues #262/#259)")
  func unembeddedCandidateIsNotScored() async throws {
    // Engine drops candidates without an `EpisodeEmbedding` row instead of
    // assigning the old neutral-0.5 prior — a missing entry is the contract
    // PodcastDetail rec-score sort relies on to filter embedding-less rows.
    // Focused decone is still pinned so the embedded sibling produces a
    // measurable similarity on this tiny fixture.
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Loved") || text.contains("Embedded Candidate") { return [1, 0, 0] }
      return [0, 0, 1]
    }

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

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
    #expect(scores[embeddedCandidate.id] != nil)
    #expect(scores[unembeddedCandidate.id] == nil)
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
