// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Rows seeded at an older recipe version stand in for vectors the previous
// recipe left behind under the same model revision, as an app update that
// bumps `EmbeddingService.recipeVersion` finds them. Focused mode keeps
// whitening to mean-centering, since stripping three principal components
// collapses every 3-dim residual to zero.
@Suite("Recommendation scoring across embedding recipe versions", .container)
class MixedRecipeScoringTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private static let previousRecipeVersion = EmbeddingService.recipeVersion - 1
  private static let vectorFor: @Sendable (String) -> [Double] = { text in
    if text.contains("Signal") { return [1, 0, 0] }
    if text.contains("Filler") { return [0, 0, 1] }
    return [0, 1, 0]
  }

  private func seedPreviousRecipe(_ episodes: [Episode], vector: [Float]) async throws {
    try await recommendationRepo.upsertEmbeddings(
      episodes.map { episode in
        UnsavedEpisodeEmbedding(
          episodeId: episode.id,
          vector: UnsavedEpisodeEmbedding.vectorData(from: vector),
          sourceHash: "previous-recipe-\(episode.id)",
          embeddingRevision: Container.shared.contextualEmbedding().revision,
          recipeVersion: Self.previousRecipeVersion,
          dimension: vector.count,
          verificationDate: Date()
        )
      }
    )
  }

  @Test("the whitening transform follows rows re-embedded under the current recipe")
  func whiteningFollowsRecipeReembedding() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let model = ScriptedEmbeddable(vectorFor: Self.vectorFor)

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
    try await RecommendationHelpers.embedEpisodes(signals + targets, embeddable: model)

    // Under the previous recipe the fillers lie along the signals, pulling the
    // corpus mean onto them, so centered on it the target points away.
    try await seedPreviousRecipe(fillers, vector: [1, 0, 0])
    let target = try #require(targets.first)
    let early = try #require(
      try await RecommendationHelpers.startAndWaitForScores(for: targets)[target.id]
    )
    #expect(!early.reasons.contains(.similarToLiked))

    // Re-embedding the fillers in place moves the mean off the signals far
    // enough that, centered on it, the target leans toward them.
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: model)
    let engine = Container.shared.recommendationEngine()
    let late = try await RecommendationHelpers.waitAdvancing { () -> RecommendationScore? in
      guard let score = try await engine.recommendations(for: [target])[target.id],
        score.reasons.contains(.similarToLiked)
      else { return nil }
      return score
    }
    #expect(late.value > early.value)
  }

  @Test("rows embedded under an older recipe keep scoring until re-embedded")
  func previousRecipeRowsStillScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidate",
      podcastDescription: "Candidate",
      episodeDescriptions: ["Candidate", "Candidate"]
    )
    try await seedPreviousRecipe(signals, vector: [1, 0, 0])
    try await seedPreviousRecipe(candidates, vector: [0, 1, 0])

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: candidates)
    #expect(candidates.allSatisfy { scores[$0.id] != nil })
  }
}
