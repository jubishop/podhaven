// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring display-state tests", .container)
@MainActor final class RecommendationScoringDisplayTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "recommendationDisplay reflects an in-flight refresh while rec-sort is active and clears once scores apply"
  )
  func recommendationDisplayToggles() async throws {
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

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == candidateEpisodes.count
      },
      { @MainActor in
        "Expected target podcast loaded with \(candidateEpisodes.count) episodes."
      }
    )

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set(candidateEpisodes.map(\.id)))

    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.recommendationDisplay == .computing },
      { @MainActor in
        """
        Expected recommendationDisplay to be .computing while the rec-sort \
        scoring pass is in flight.
        actual: \(viewModel.recommendationDisplay)
        """
      }
    )

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.recommendationDisplay == .idle },
      { @MainActor in
        """
        Expected recommendationDisplay to return to .idle once scoring completes.
        actual: \(viewModel.recommendationDisplay)
        """
      }
    )
  }

  @Test(
    "recommendationDisplay clears to .idle when the scoring pass returns early on an empty entries list"
  )
  func recommendationDisplayClearsOnEmptyEntriesEarlyReturn() async throws {
    // Unsaved VM with zero episodes — the immediate scoring pass scheduled
    // from the rec-sort setter exits via the `entries.isEmpty` early-return
    // in `computeAndPublishRecommendationScores`. That path must still
    // clear the `.computing` banner.
    let unsavedPodcast = try Create.unsavedPodcast(
      title: "Empty Podcast",
      description: "Empty Podcast"
    )

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(unsavedPodcast))

    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.recommendationDisplay == .idle },
      { @MainActor in
        """
        Expected recommendationDisplay to return to .idle once the scoring \
        pass exited via the empty-entries early-return.
        actual: \(viewModel.recommendationDisplay)
        """
      }
    )
  }
}
