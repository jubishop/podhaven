// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring disappear cancellation tests", .container)
@MainActor final class RecommendationScoringDisappearTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.sleeper) private var sleeperFactory

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  private var fakeSleeper: FakeSleeper { sleeperFactory as! FakeSleeper }

  @Test(
    "disappear cancels the in-flight immediate scoring task so its runningDirty rerun is dropped"
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
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let targetIDs = Set(candidateEpisodes.map(\.id))
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

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

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the bootstrap scoring pass to suspend on the gated embeddings call." }
    )

    // Force the coalescer into `.runningDirty` so the surrounding `repeat`
    // loop would re-run compute and call embeddings again on resume — unless
    // disappear cancels the in-flight task and the `!Task.isCancelled` guard
    // in the loop exits cleanly.
    let pendingSleepRequests = fakeSleeper.pendingCount()
    recommendationEngine.$contextRevision.update { $0 += 1 }
    try await fakeSleeper.waitForSleepRequests(count: pendingSleepRequests + 1)
    await fakeSleeper.advanceTime(by: .seconds(1))
    for _ in 0..<3 {
      await Task.yield()
    }

    viewModel.disappear()
    fakeRecommendationRepo.clearAllCalls()
    fakeRepo.releaseEmbeddingsGate()

    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .seconds(2))

    let postDisappearCalls = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
      matching: targetIDs
    )
    #expect(
      postDisappearCalls == 0,
      """
      Expected disappear() to cancel the in-flight immediate scoring task. \
      Instead, \(postDisappearCalls) embeddings(for:) calls fired for the \
      target IDs after disappear — the runningDirty rerun completed on a \
      torn-down view model.
      """
    )
  }
}
