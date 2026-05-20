// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring stale-snapshot publish tests", .container)
@MainActor final class RecommendationScoringStaleSnapshotTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "a scoring pass against a stale list-identity must not overwrite scores from a newer pass"
  )
  func staleListIdentityMustNotOverwriteNewerScores() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let feedURL = FeedURL(URL(string: "https://example.com/stale-snapshot.rss")!)
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: feedURL,
          title: "Target",
          description: "Target"
        ),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "target-0",
            title: "Target 0",
            pubDate: Date(timeIntervalSince1970: 100),
            description: "Target 0"
          ),
          try Create.unsavedEpisode(
            guid: "target-1",
            title: "Target 1",
            pubDate: Date(timeIntervalSince1970: 200),
            description: "Target 1"
          ),
          try Create.unsavedEpisode(
            guid: "target-2",
            title: "Target 2",
            pubDate: Date(timeIntervalSince1970: 300),
            description: "Target 2"
          ),
          try Create.unsavedEpisode(
            guid: "target-3",
            title: "Target 3",
            pubDate: Date(timeIntervalSince1970: 400),
            description: "Target 3"
          ),
        ]
      )
    )
    let savedEpisodes = Array(savedSeries.episodes)
    try await RecommendationHelpers.embedEpisodes(savedEpisodes, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: savedEpisodes)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()

    let initialIDs = Set(savedEpisodes.map(\.id))
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in
        viewModel.saved
          && Set(viewModel.episodeList.allEntries.compactMap(\.episodeID)) == initialIDs
      },
      { @MainActor in
        """
        Expected all four target episodes to load before arming the gate.
        ids: \(viewModel.episodeList.allEntries.compactMap(\.episodeID))
        """
      }
    )

    viewModel.currentSortMethod = .recommendationScore
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == initialIDs
      },
      { @MainActor in
        """
        Expected rec-score sort to apply against the initial four episodes.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )

    let newGUID = GUID("target-4")
    let newPubDate = Date(timeIntervalSince1970: 500)

    await RecommendationScoringTestHelpers.drainRecommendationSleeper()

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.clearAllCalls()
    fakeRepo.armEmbeddingsGate(matching: initialIDs)
    recommendationEngine.$contextRevision.update { $0 += 1 }

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected scoring pass to suspend on gated embeddings call before list change." }
    )

    try await repo.updateSeriesFromFeed(
      podcastSeries: savedSeries,
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: newGUID,
          title: "Target 4",
          pubDate: newPubDate,
          description: "Target 4"
        )
      ],
      existingEpisodes: []
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.allEntries.count == 5 },
      { @MainActor in
        """
        Expected observation to grow the list to five episodes before releasing the stale pass.
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let newEpisode = try #require(
      viewModel.episodeList.allEntries.first { $0.mediaGUID.guid == newGUID }
    )
    let newEpisodeID = try #require(newEpisode.episodeID)
    let newEpisodeModel = try #require(try await repo.episode(newEpisodeID))
    try await RecommendationHelpers.embedEpisodes([newEpisodeModel], embeddable: embeddable)

    fakeRepo.releaseEmbeddingsGate()

    let expectedIDs = initialIDs.union([newEpisodeID])
    try await RecommendationScoringTestHelpers.waitForScopedEmbeddingsCalls(
      matching: expectedIDs,
      atLeast: 1,
      reason: "Expected stale-pass discard to rerun scoring against the newer list-identity."
    )
    await RecommendationScoringTestHelpers.drainRecommendationSleeper()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == expectedIDs
      },
      { @MainActor in
        """
        Stale scoring pass overwrote scores from the newer list-identity.
        Expected all 5 episodes visible under rec-score sort.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }
}
