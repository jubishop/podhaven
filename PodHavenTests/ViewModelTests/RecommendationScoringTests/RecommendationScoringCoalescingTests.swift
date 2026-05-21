// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring coalescing tests", .container)
@MainActor final class RecommendationScoringCoalescingTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.sleeper) private var sleeperFactory

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  private var fakeSleeper: FakeSleeper { sleeperFactory as! FakeSleeper }

  @Test(
    "a burst of $scoringRevision bumps must coalesce into 1...2 scoring passes"
  )
  func burstContextRevisionBumpsCoalesce() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 6,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: (0..<6).map { "Target \($0)" }
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

    // Drain the bootstrap pass so we only measure the burst's fan-out.
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) >= 1
        }
      },
      { @MainActor in
        "Expected at least one initial scoring pass before the burst."
      }
    )
    // Quiesce setup-driven rebuilds: a late $scoringRevision bump landing
    // during the burst's pass would add an uncounted-for rerun.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    fakeRecommendationRepo.clearAllCalls()

    let pendingSleepRequests = fakeSleeper.pendingCount()
    for _ in 0..<50 {
      recommendationEngine.$scoringRevision.update { $0 += 1 }
    }
    try await fakeSleeper.waitForSleepRequests(count: pendingSleepRequests + 1)

    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: targetIDs,
      atLeast: 1,
      reason: "Expected the debounced burst refresh to perform one scoring pass."
    )
    await RecommendationScoringTestHelpers.drainRecommendationSleeper(by: .milliseconds(400))

    let count = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs)
    #expect(
      (1...2).contains(count),
      """
      Expected per-VM coalescing to bound the scoring fan-out, but \(count) \
      scoring passes fired for the same candidate set during a burst of 50 \
      $scoringRevision bumps. The contract is exactly one trailing pass per \
      debounce window, plus at most one runningDirty rerun.
      """
    )
  }

  @Test(
    "a $scoringRevision bump landing while a scoring pass is suspended must rerun once the pass releases, not be lost to the debounce re-trigger"
  )
  func scoringRevisionBumpDuringSuspendedPassReruns() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: (0..<4).map { "Target \($0)" }
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

    // Quiesce every rebuild the setup writes triggered. Otherwise a late
    // $scoringRevision bump could reschedule the stranded pass and mask the
    // regression: the bug is that the bump-driven rerun is lost on its own.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.clearAllCalls()

    // Bump #1 drives a scoring pass that suspends mid-flight on the gated
    // embeddings read.
    fakeRepo.armEmbeddingsGate(matching: targetIDs)
    recommendationEngine.$scoringRevision.update { $0 += 1 }
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the first scoring pass to suspend on the gated embeddings read." }
    )

    // Bump #2 lands while that pass is still suspended. Wait for its debounce
    // window to arm, then fire it — re-triggering the debounce against the
    // still-in-flight pass. The pass must survive that re-trigger and rerun
    // for the newer revision once released.
    let pendingBeforeBump2 = fakeSleeper.pendingCount()
    recommendationEngine.$scoringRevision.update { $0 += 1 }
    try await fakeSleeper.waitForSleepRequests(count: pendingBeforeBump2 + 1)
    await RecommendationScoringTestHelpers.drainRecommendationSleeper()

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: targetIDs,
      atLeast: 2,
      reason: """
        A $scoringRevision bump that arrived while a scoring pass was \
        suspended was dropped: the pass never reran for the newer revision.
        """
    )
  }

  @Test(
    "while .recommendationScore is active, a $scoringRevision bump triggers a coalesced refresh that updates the visible order"
  )
  func activeRecSortLiveUpdatesAfterCoalescedRefresh() async throws {
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Fresh Signal") { return [0, 1, 0] }
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"]
      )
    try await RecommendationHelpers.embedEpisodes(
      candidateEpisodes,
      embeddable: embeddable
    )
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)
    let newestFirstOrder =
      candidateEpisodes
      .sorted { $0.pubDate > $1.pubDate }
      .map(\.id)

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

    let initialOrder: [Episode.ID] = try await RecommendationHelpers.waitAdvancing {
      let order = await MainActor.run {
        viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
      }
      return order.count == candidateEpisodes.count && order != newestFirstOrder
        ? order
        : nil
    }

    let (_, freshSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 12,
      podcastTitle: "Fresh Signal",
      podcastDescription: "Fresh Signal",
      episodeDescriptions: Array(repeating: "Fresh Signal", count: 12),
      ratings: Array(repeating: .loved, count: 12)
    )
    try await RecommendationHelpers.embedEpisodes(freshSignals, embeddable: embeddable)

    let engine = recommendationEngine
    let revisionBeforeRefresh = engine.scoringRevision
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { engine.scoringRevision > revisionBeforeRefresh },
      {
        """
        Expected embedding the fresh signal episodes to rebuild the scoring \
        context and bump $scoringRevision.
        before: \(revisionBeforeRefresh)
        current: \(engine.scoringRevision)
        """
      }
    )

    let refreshedScores = try await engine.recommendations(for: candidateEpisodes)
    let expectedOrder = RecommendationScoringTestHelpers.recommendationOrder(
      candidateEpisodes,
      scores: refreshedScores
    )
    try #require(
      expectedOrder != initialOrder,
      """
      Adding fresh signals must produce a different rec-score order; otherwise \
      the test cannot observe the live-update.
      """
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        let order = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
        return order == expectedOrder
      },
      { @MainActor in
        """
        Expected coalesced refresh to publish an updated rec-score order.
        Initial: \(initialOrder)
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }
}
