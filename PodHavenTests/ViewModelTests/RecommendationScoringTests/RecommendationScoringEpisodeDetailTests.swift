// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM.
@Suite("of recommendation scoring EpisodeDetailViewModel tests", .container)
@MainActor final class RecommendationScoringEpisodeDetailTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "EpisodeDetailViewModel observes the first scoringRevision emitted immediately after recommendation observation starts"
  )
  func episodeDetailDoesNotDropFirstScoringRevisionAfterObservationStarts() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0"]
    )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetEpisodeID = try #require(candidateEpisodes.first?.id)
    let podcastEpisode = try #require(try await repo.podcastEpisode(targetEpisodeID))

    let fakeRepo = fakeRecommendationRepo
    let targetIDs = Set([targetEpisodeID])
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await EpisodeDetailTestHelpers.appear(viewModel)

    // The bootstrap scoring pass suspends on the gated embeddings call.
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected bootstrap scoring to suspend on the gated embeddings call." }
    )

    fakeRecommendationRepo.clearAllCalls()
    recommendationEngine.$scoringRevision.update { $0 += 1 }

    // The scoringRevision bump emitted right after observation starts must not
    // be dropped: it cancels the gated bootstrap pass and restarts a fresh one,
    // which scores the target episode again.
    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: targetIDs,
      atLeast: 1,
      reason: "Expected the post-start scoringRevision bump to trigger a re-score."
    )

    fakeRepo.releaseEmbeddingsGate()
  }

  @Test(
    "EpisodeDetailViewModel drops a stale bootstrap recommendation if a newer context refresh publishes first"
  )
  func episodeDetailStaleContextFetchDoesNotOverwriteNewerScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    Container.shared.userSettings().$podcastAffinityWeight.new(0)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Anchor") { return [0, 1, 0] }
      if text.contains("Old Signal") { return [1, 0, 0] }
      if text.contains("Fresh Signal") { return [0, 1, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, oldSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Old Signal",
      podcastDescription: "Old Signal",
      episodeDescriptions: Array(repeating: "Old Signal", count: 3),
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(oldSignals, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: oldSignals)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target", "Anchor"],
      pubDateOffset: { index in index == 0 ? -90 * 86400 : 0 }
    )
    try await RecommendationHelpers.embedEpisodes(
      candidateEpisodes,
      embeddable: embeddable
    )
    let targetEpisode = try #require(candidateEpisodes.first)
    let targetID = targetEpisode.id
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let podcastEpisode = try #require(try await repo.podcastEpisode(targetID))
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set([targetID]))

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await EpisodeDetailTestHelpers.appear(viewModel)

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the bootstrap recommendation fetch to suspend." }
    )

    // Fresh "loved" signals refresh the scoring context. The resulting
    // $scoringRevision bump cancels the gated bootstrap pass and re-scores the
    // target against the new context.
    let (_, freshSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 12,
      podcastTitle: "Fresh Signal",
      podcastDescription: "Fresh Signal",
      episodeDescriptions: Array(repeating: "Fresh Signal", count: 12),
      ratings: Array(repeating: .loved, count: 12)
    )
    try await RecommendationHelpers.embedEpisodes(freshSignals, embeddable: embeddable)

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected the context-refresh re-score to land a recommendation score.
        actual: \(String(describing: viewModel.displayedScore))
        """
      }
    )
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    guard case .recommendation(let freshScore) = viewModel.displayedScore else {
      Issue.record(
        "Expected a fresh recommendation score, got \(String(describing: viewModel.displayedScore))"
      )
      return
    }

    // Releasing the gated bootstrap embeddings call lets the now-cancelled
    // stale pass drain. Its old-context result must be dropped, never written
    // over the fresh score.
    fakeRepo.releaseEmbeddingsGate()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    guard case .recommendation(let finalScore) = viewModel.displayedScore else {
      Issue.record(
        "Expected the final score to remain a recommendation, got \(String(describing: viewModel.displayedScore))"
      )
      return
    }
    #expect(
      abs(finalScore.value - freshScore.value) < 0.001,
      """
      The stale bootstrap fetch overwrote the newer context-refresh score.
      freshScore: \(freshScore.value)
      finalScore: \(finalScore.value)
      """
    )
  }

  @Test(
    "EpisodeDetailViewModel re-attempts a saved-side score on the next appear after a transient embedding-fetch error"
  )
  func episodeDetailReattemptsAfterTransientEmbeddingFetchError() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Recovery",
      podcastDescription: "Recovery",
      episodeDescriptions: ["Recovery 0"]
    )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)
    // Pin scoringRevision before the first appear so the second appear's
    // snapshot is identical to the first — the only path that exercises the
    // cache. A late engine rebuild would invalidate the cache for the wrong
    // reason and pass the test by accident.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let targetEpisodeID = try #require(candidateEpisodes.first?.id)
    let podcastEpisode = try #require(try await repo.podcastEpisode(targetEpisodeID))

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.embeddingFetchError { $0 = TestError.simulatedFailure }

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await EpisodeDetailTestHelpers.appear(viewModel)

    // First appear: the saved-side pass hits the armed error. Wait until the
    // one-shot has been consumed so we know the pass actually ran (rather than
    // racing past the assertion before the error reached scoreSavedEpisode).
    try await Wait.until(
      priority: .userInitiated,
      { fakeRepo.embeddingFetchError() == nil },
      { "Expected the armed embedding-fetch error to be consumed by the first pass." }
    )
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    #expect(viewModel.displayedScore == nil)

    // Disappear + reappear with no error armed and the same scoringRevision.
    // A coordinator that cached the error-produced nil will replay it; a
    // coordinator that didn't cache will re-attempt and land .recommendation.
    viewModel.disappear()
    try await EpisodeDetailTestHelpers.appear(viewModel)

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Reappearing after a transient embedding-fetch error left the detail \
        view stuck on the cached error-produced nil instead of re-attempting.
        score: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }
}
