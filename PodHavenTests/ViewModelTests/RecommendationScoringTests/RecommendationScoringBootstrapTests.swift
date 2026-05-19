// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring bootstrap tests", .container)
@MainActor final class RecommendationScoringBootstrapTests {
  @DynamicInjected(\.repo) private var repo

  @Test(
    "background scoring on .newestFirst caches scores so a later switch to .recommendationScore applies them"
  )
  func backgroundPrewarmingAppliesWithoutRefetch() async throws {
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

    // Gating all scoring behind `.recommendationScore` would fail this:
    // nothing would score on .newestFirst.
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) >= 1
        }
      },
      {
        await MainActor.run {
          """
          Expected background prewarming to fetch embeddings while on .newestFirst.
          calls: \(RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs))
          """
        }
      }
    )

    let newestFirstOrder = viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.count == candidateEpisodes.count
          && viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
            != newestFirstOrder
      },
      { @MainActor in
        """
        Expected prewarmed scores to apply on switch to .recommendationScore.
        Pre-switch (newestFirst) order: \(newestFirstOrder)
        Post-switch order: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "PodcastDetailViewModel opened against a hot engine cache scores without a subsequent $contextRevision bump"
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
        $contextRevision bump arrives.
        Newest-first: \(newestFirstOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel opened against a hot engine cache surfaces a displayedScore without a subsequent $contextRevision bump"
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
        saved episode without a subsequent $contextRevision bump.
        displayedScore: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }
}
