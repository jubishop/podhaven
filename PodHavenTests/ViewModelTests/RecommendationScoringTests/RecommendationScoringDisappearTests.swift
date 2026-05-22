// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring disappear/re-appear tests", .container)
@MainActor final class RecommendationScoringDisappearTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "disappear cancels the in-flight scoring pass so it never publishes after teardown"
  )
  func disappearCancelsInflightScoringPass() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"]
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)

    // A second unrated podcast widens the engine's global candidate pool, so
    // the engine's own rebuilds fetch embeddings for a superset of IDs. Only a
    // VM scoring pass scores exactly its podcast's episodes, so an `embeddings`
    // call whose ID set equals `targetIDs` — and the armed gate — is unique
    // to the view model under test.
    let (_, decoyEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Decoy",
        podcastDescription: "Decoy",
        episodeDescriptions: ["Decoy 0", "Decoy 1", "Decoy 2", "Decoy 3"]
      )
    try await RecommendationHelpers.embedEpisodes(decoyEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetIDs = Set(candidateEpisodes.map(\.id))

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(targetPodcast))
    try await viewModel.performAppear()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        "Expected target podcast loaded with \(candidateEpisodes.count) episodes."
      }
    )

    // Quiesce engine rebuilds, then gate the VM's on-demand scoring pass.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the on-demand scoring pass to suspend on the gated embeddings read." }
    )

    viewModel.disappear()
    fakeRepo.clearAllCalls()
    fakeRepo.releaseEmbeddingsGate()

    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .seconds(2))

    let postDisappearCalls = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
      matching: targetIDs
    )
    #expect(
      postDisappearCalls == 0,
      """
      Expected disappear() to cancel the in-flight scoring pass. Instead, \
      \(postDisappearCalls) embeddings(for:) calls fired for the target IDs \
      after disappear — a torn-down scoring pass reran.
      """
    )
  }

  @Test(
    "re-appearing with the rec sort still selected resumes the scoring-revision observation"
  )
  func reappearResumesScoringForActiveRecSort() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"]
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)

    // A second unrated podcast widens the engine's global candidate pool, so
    // only a VM scoring pass produces an `embeddings` call whose ID set equals
    // `targetIDs` — the engine's own rebuilds fetch a superset.
    let (_, decoyEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Decoy",
        podcastDescription: "Decoy",
        episodeDescriptions: ["Decoy 0", "Decoy 1", "Decoy 2", "Decoy 3"]
      )
    try await RecommendationHelpers.embedEpisodes(decoyEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetIDs = Set(candidateEpisodes.map(\.id))

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(targetPodcast))
    try await viewModel.performAppear()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        "Expected target podcast loaded with \(candidateEpisodes.count) episodes."
      }
    )

    viewModel.currentSortMethod = .recommendationScore
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.recommendationDisplay == .idle },
      { @MainActor in "Expected the first on-demand scoring pass to settle." }
    )
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.recommendationDisplay == .idle },
      { @MainActor in "Expected the rec sort to be idle once the engine settled." }
    )

    // Disappear tears the scoring-revision observation down; re-appearing with
    // the rec sort still selected must resume it.
    viewModel.disappear()
    try await viewModel.performAppear()

    fakeRecommendationRepo.clearAllCalls()
    recommendationEngine.$scoringRevision.update { $0 += 1 }

    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: targetIDs,
      atLeast: 1,
      reason: """
        After re-appearing with the rec sort selected, a $scoringRevision bump \
        did not trigger a rescore — the scoring-revision observation was not \
        resumed on performAppear().
        """
    )
  }
}
