// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring bootstrap tests", .container)
@MainActor final class RecommendationScoringBootstrapTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test("a non-rec sort never starts recommendation scoring work")
  func recommendationWorkDoesNotRunOnNonRecSort() async throws {
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
    // VM scoring pass — which scores exactly its podcast's episodes — produces
    // an `embeddings` call whose ID set equals `targetIDs`.
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
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    fakeRecommendationRepo.clearAllCalls()

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

    // Poll a window, advancing the production sleeper each iteration so any
    // debounced/scheduled scoring work would fire. While the sort stays
    // .newestFirst, the recommendation scoring pass — which fetches embeddings
    // for exactly the candidate set — must never run.
    let fakeSleeper = Container.shared.sleeper() as! FakeSleeper
    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(20),
        priority: .userInitiated,
        {
          await fakeSleeper.advanceTime(by: .milliseconds(400))
          return await MainActor.run {
            RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) >= 1
          }
        },
        { "regression sentinel — see Issue.record below" }
      )
      Issue.record(
        """
        regression: a non-rec sort ran a recommendation scoring pass. Scoring \
        must only run on demand, while the .recommendationScore sort is selected.
        """
      )
    } catch {
      // Expected timeout under the fixed implementation.
    }

    #expect(RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) == 0)
  }

  @Test(
    "switching to .recommendationScore on demand scores and applies the rec-score order"
  )
  func onDemandSortSelectionAppliesScores() async throws {
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
        """
        Expected target podcast to load all \(candidateEpisodes.count) candidates.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let newestFirstOrder = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
    viewModel.currentSortMethod = .recommendationScore

    // Selecting the rec sort is the sole trigger: scoring fetches embeddings
    // for exactly the candidate set, then applies the rec-score order.
    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: targetIDs,
      atLeast: 1,
      reason: "Expected selecting .recommendationScore to run a scoring pass."
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == candidateEpisodes.count
          && viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
            != newestFirstOrder
      },
      { @MainActor in
        """
        Expected on-demand scores to apply on switch to .recommendationScore.
        Pre-switch (newestFirst) order: \(newestFirstOrder)
        Post-switch order: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "PodcastDetailViewModel opened against a hot engine cache scores without a subsequent $scoringRevision bump"
  )
  func podcastDetailHotCacheBootstrapScoresImmediately() async throws {
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

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        let order = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
        return order.count == candidateEpisodes.count && order != newestFirstOrder
      },
      { @MainActor in
        """
        Expected initial bootstrap scoring to populate the rec-score sort even \
        when the engine cache is already hot and no further \
        $scoringRevision bump arrives.
        Newest-first: \(newestFirstOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel opened against a hot engine cache surfaces a displayedScore without a subsequent $scoringRevision bump"
  )
  func episodeDetailHotCacheBootstrapScoresImmediately() async throws {
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
    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))

    try await viewModel.performAppear()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected hot-cache bootstrap to surface a recommendation score for the \
        saved episode without a subsequent $scoringRevision bump.
        displayedScore: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }
}
