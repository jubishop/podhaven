// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring cached-snapshot fast-path tests", .container)
@MainActor final class RecommendationScoringFastPathTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "a transition whose snapshot equals the cached snapshot must not trigger a redundant scoring pass"
  )
  func sameSnapshotTransitionSkipsRedundantCompute() async throws {
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
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(targetPodcast))
    try await viewModel.performAppear()

    let targetIDs = Set(candidateEpisodes.map(\.id))
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        "Expected target podcast loaded with \(candidateEpisodes.count) episodes."
      }
    )

    // Drive the bootstrap pass to publish. Switching to .recommendationScore
    // and seeing the rec-score order land proves the score cache is populated
    // — the setter only applies cached.scores when cached.snapshot equals the
    // current snapshot, and the filteredEntries shift reflects that apply.
    let preRecOrder = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
    viewModel.currentSortMethod = .recommendationScore
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        let order = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
        return order.count == candidateEpisodes.count && order != preRecOrder
      },
      { @MainActor in
        """
        Expected rec-score sort to land before the same-snapshot transition.
        order: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
    viewModel.currentSortMethod = .newestFirst

    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .seconds(2))
    fakeRecommendationRepo.clearAllCalls()

    // markFinished writes finishDate / currentTime / maxPlaybackTime — none
    // are in the recommendation-scoring snapshot (mediaGUID, episodeID,
    // pubDate). The observed PodcastSeriesDetail will change and transition()
    // will fire, but the cached snapshot still equals the current one.
    let targetEpisodeID = try #require(candidateEpisodes.first?.id)
    _ = try await repo.markFinished(targetEpisodeID)

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.allEntries.contains {
          $0.episodeID == targetEpisodeID && $0.finished
        }
      },
      { @MainActor in
        "Expected observation to surface the finishedDate update on the target episode."
      }
    )

    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .seconds(2))

    let postTransitionCalls = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
      matching: targetIDs
    )
    #expect(
      postTransitionCalls == 0,
      """
      Expected the cached-snapshot fast path to skip the embedding round-trip \
      for a same-snapshot transition, but \(postTransitionCalls) embeddings(for:) \
      calls fired after marking an episode finished — the cache check failed to \
      prevent the redundant compute.
      """
    )
  }
}
