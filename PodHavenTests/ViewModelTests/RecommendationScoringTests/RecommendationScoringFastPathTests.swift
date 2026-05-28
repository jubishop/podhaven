// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM.
@Suite("of recommendation scoring retained-score fast-path tests", .container)
@MainActor final class RecommendationScoringFastPathTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "re-selecting the rec sort with an unchanged candidate set reuses the retained score without recomputing"
  )
  func reselectingRecSortReusesRetainedScore() async throws {
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
    try await PodcastDetailTestHelpers.appear(viewModel)
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        "Expected target podcast loaded with \(candidateEpisodes.count) episodes."
      }
    )

    // First selection scores the candidates and applies the rec-score order.
    viewModel.currentSortMethod = .recommendationScore
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        """
        Expected the first on-demand scoring pass to land all target entries.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
    // Quiesce the engine so the retained snapshot's revision stays put across
    // the sort round-trip below.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let recOrder = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)

    viewModel.currentSortMethod = .newestFirst
    fakeRecommendationRepo.clearAllCalls()

    // Nothing in the scoring snapshot changed. Re-selecting must reuse the
    // retained score — no re-scoring embeddings call.
    viewModel.currentSortMethod = .recommendationScore

    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .seconds(2))

    #expect(viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == recOrder)

    let calls = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs)
    #expect(
      calls == 0,
      """
      Expected the retained score to short-circuit a recompute, but \(calls) \
      embeddings(for:) calls fired for the target IDs on re-selection.
      """
    )
  }
}
