// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// The container's model is revision 1, the `ScriptedEmbeddable` default, so
// rows embedded at another revision stand in for vectors an earlier model left
// behind. Focused mode keeps whitening to mean-centering, since stripping three
// principal components collapses every 3-dim residual to zero.
@Suite("Recommendation scoring across embedding revisions", .container)
class MixedRevisionScoringTests {
  private static let previousRevision = 2

  @Test("candidates embedded under another revision get no score")
  func otherRevisionCandidatesGetNoScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let vectorFor: @Sendable (String) -> [Double] = { text in
      text.contains("Signal") ? [1, 0, 0] : [0, 1, 0]
    }
    let currentModel = ScriptedEmbeddable(vectorFor: vectorFor)
    let previousModel = ScriptedEmbeddable(revision: Self.previousRevision, vectorFor: vectorFor)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: currentModel)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidate",
      podcastDescription: "Candidate",
      episodeDescriptions: ["Candidate", "Candidate"]
    )
    let current = try #require(candidates.first)
    let stale = try #require(candidates.last)
    try await RecommendationHelpers.embedEpisodes([current], embeddable: currentModel)
    try await RecommendationHelpers.embedEpisodes([stale], embeddable: previousModel)

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: candidates)
    #expect(scores[current.id] != nil)
    #expect(scores[stale.id] == nil)

    let pool = try await Container.shared.recommendationEngine().topRecommendations(limit: 10)
    #expect(!pool.contains(stale.id))
  }

  @Test("signals embedded under another revision do not move the centroid")
  func otherRevisionSignalsDoNotMoveCentroid() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let vectorFor: @Sendable (String) -> [Double] = { text in
      text.contains("Signal") ? [1, 0, 0] : [0, 1, 0]
    }
    let currentModel = ScriptedEmbeddable(vectorFor: vectorFor)
    let previousModel = ScriptedEmbeddable(revision: Self.previousRevision, vectorFor: vectorFor)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal"],
      ratings: [.loved]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: currentModel)

    // Outweighing the current signal, these would pull the centroid onto the
    // target if they counted.
    let (_, staleSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Echo",
      podcastDescription: "Echo",
      episodeDescriptions: ["Echo", "Echo", "Echo"],
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(staleSignals, embeddable: previousModel)

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: currentModel)

    let target = try #require(targets.first)
    let scores = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    let score = try #require(scores[target.id])
    #expect(!score.reasons.contains(.similarToLiked))
  }

  @Test("the whitening transform follows rows re-embedded under the current revision")
  func whiteningFollowsReembedding() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let vectorFor: @Sendable (String) -> [Double] = { text in
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Filler") { return [0, 0, 1] }
      return [0, 1, 0]
    }
    let currentModel = ScriptedEmbeddable(vectorFor: vectorFor)
    let previousModel = ScriptedEmbeddable(revision: Self.previousRevision, vectorFor: vectorFor)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target"]
    )
    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 12,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 12)
    )
    try await RecommendationHelpers.embedEpisodes(
      signals + targets + fillers,
      embeddable: previousModel
    )

    // Centered on the mean of the signals and the target alone, the target
    // points away from the signals.
    try await RecommendationHelpers.embedEpisodes(signals + targets, embeddable: currentModel)
    let target = try #require(targets.first)
    let early = try #require(
      try await RecommendationHelpers.startAndWaitForScores(for: targets)[target.id]
    )
    #expect(!early.reasons.contains(.similarToLiked))

    // The fillers move the corpus mean far enough that, centered on it, the
    // target leans toward the signals.
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: currentModel)
    let engine = Container.shared.recommendationEngine()
    let late = try await RecommendationHelpers.waitAdvancing { () -> RecommendationScore? in
      guard let score = try await engine.recommendations(for: [target])[target.id],
        score.reasons.contains(.similarToLiked)
      else { return nil }
      return score
    }
    #expect(late.value > early.value)
  }
}
