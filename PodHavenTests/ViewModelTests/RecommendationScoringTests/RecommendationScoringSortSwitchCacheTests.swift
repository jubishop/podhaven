// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM.
@Suite("of recommendation scoring sort-switch cache tests", .container)
@MainActor final class RecommendationScoringSortSwitchCacheTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "re-selecting the rec sort after an episode's pubDate changed recomputes instead of reusing the stale retained score"
  )
  func reselectingAfterSnapshotChangeRecomputes() async throws {
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
    // the armed gate — which matches an exact ID set — only catches the VM's
    // scoring pass, not the engine's broader rebuilds.
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
        viewModel.saved
          && Set(viewModel.episodeList.allEntries.compactMap(\.episodeID)) == targetIDs
      },
      { @MainActor in "Expected all target episodes to load." }
    )

    // Select the rec sort once to populate the retained score, then settle.
    viewModel.currentSortMethod = .recommendationScore
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
      },
      { @MainActor in
        """
        Expected the first on-demand scoring pass to land all target entries.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
    viewModel.currentSortMethod = .newestFirst
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    // Change an episode's pubDate — part of the scoring snapshot. The list row
    // updates while on .newestFirst, but no rescore runs off the rec sort.
    let updatedEpisodeID = try #require(candidateEpisodes.first?.id)
    let updatedPubDate = Date().addingTimeInterval(.days(7))
    try await appDB.db.write { db in
      _ =
        try Episode
        .withID(updatedEpisodeID)
        .updateAll(db, Episode.Columns.pubDate.set(to: updatedPubDate))
    }
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        guard
          let updated = viewModel.episodeList.allEntries.first(where: {
            $0.episodeID == updatedEpisodeID
          })
        else { return false }
        return abs(updated.pubDate.timeIntervalSince(updatedPubDate)) < 1
      },
      { @MainActor in "Expected observation to surface the episode's new pubDate." }
    )

    // Re-selecting the rec sort: the retained score's snapshot no longer
    // matches (the pubDate changed), so it must recompute. The armed gate
    // suspends that pass — proving the recompute ran, not the retained score.
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: targetIDs)
    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the re-selection recompute to fetch embeddings for the candidate set." }
    )
    fakeRepo.releaseEmbeddingsGate()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
  }
}
