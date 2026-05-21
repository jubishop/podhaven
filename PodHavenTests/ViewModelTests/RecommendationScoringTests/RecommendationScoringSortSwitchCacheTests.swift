// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of recommendation scoring sort-switch cache tests", .container)
@MainActor final class RecommendationScoringSortSwitchCacheTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test(
    "switching to .recommendationScore while the cached scores are stale must not hide newly-arrived episodes during the refresh window"
  )
  func staleCacheOnSortSwitchDoesNotHideNewEpisodes() async throws {
    let embeddable = RecommendationScoringTestHelpers.scoringEmbeddable()
    try await RecommendationScoringTestHelpers.primeEngine(with: embeddable)

    let feedURL = FeedURL(URL(string: "https://example.com/stale-sort-switch.rss")!)
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
        "Expected all four initial episodes to load before priming the cache."
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
        Expected initial scoring pass to populate the rec-score sort with all \
        four episodes before adding the fifth.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
    viewModel.currentSortMethod = .newestFirst
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.filteredEntries.count == 4 },
      { @MainActor in
        "Expected sort to return to .newestFirst with all four entries visible."
      }
    )

    let newGUID = GUID("target-4")
    try await repo.updateSeriesFromFeed(
      podcastSeries: savedSeries,
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: newGUID,
          title: "Target 4",
          pubDate: Date(timeIntervalSince1970: 500),
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
        Expected observation to grow the list to five before switching to rec-score sort.
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    let newEpisode = try #require(
      viewModel.episodeList.allEntries.first { $0.mediaGUID.guid == newGUID }
    )
    let newEpisodeID = try #require(newEpisode.episodeID)
    let allIDs = initialIDs.union([newEpisodeID])

    // Settle the engine's in-flight cache rebuild + the VM's debounced refresh
    // that the new-episode insertion triggered. Without this, those pending
    // tasks land on top of the manual scoringRevision bump below and cancel
    // the gated scoring pass mid-flight.
    await RecommendationScoringTestHelpers.drainRecommendationSleeper()

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.clearAllCalls()
    fakeRepo.armEmbeddingsGate(matching: allIDs)
    recommendationEngine.$scoringRevision.update { $0 += 1 }

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the five-ID background scoring pass to suspend before cache publish." }
    )

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        let callCount = await MainActor.run {
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: allIDs)
        }
        return fakeRepo.didEmbeddingsGateComplete && callCount >= 1
      },
      { "Expected the five-ID background scoring pass to complete." }
    )
    for _ in 0..<10 {
      await Task.yield()
    }

    fakeRepo.armEmbeddingsGate(matching: allIDs)
    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the partial cached sort switch to start a visible refresh." }
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.recommendationDisplay == .computing
          && viewModel.episodeList.filteredEntries.count == 5
      },
      { @MainActor in
        """
        Applying the partial five-ID cache filtered out the newly-arrived \
        fifth episode before the foreground refresh could settle.
        display: \(viewModel.recommendationDisplay)
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.recommendationDisplay == .idle
          && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == initialIDs
      },
      { @MainActor in
        """
        Expected the settled recommendation sort to hide the still-unembedded \
        fifth episode after the foreground refresh completed.
        display: \(viewModel.recommendationDisplay)
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "switching to .recommendationScore while same-episode cached scores have stale pubDates keeps the refresh visible"
  )
  func stalePubDateCacheOnSortSwitchShowsRefresh() async throws {
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
        viewModel.saved
          && Set(viewModel.episodeList.allEntries.compactMap(\.episodeID)) == targetIDs
      },
      { @MainActor in
        "Expected all target episodes to load before priming cached scores."
      }
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      {
        await MainActor.run {
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs) >= 1
        }
      },
      { "Expected background scoring to populate the cached scores." }
    )

    viewModel.currentSortMethod = .recommendationScore
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.recommendationDisplay == .idle
          && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
      },
      { @MainActor in
        """
        Expected initial cached scores to settle before testing pubDate invalidation.
        display: \(viewModel.recommendationDisplay)
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
    viewModel.currentSortMethod = .newestFirst
    fakeRecommendationRepo.clearAllCalls()

    let updatedEpisodeID = try #require(candidateEpisodes.first?.id)
    let updatedPubDate = Date().addingTimeInterval(.days(7))
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

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
      { @MainActor in
        let entryDescriptions = viewModel.episodeList.allEntries.map {
          let episodeID = $0.episodeID.map { String(describing: $0) } ?? "nil"
          return "\(episodeID): \($0.pubDate)"
        }
        return """
          Expected observation to update the existing episode row's pubDate.
          entries: \(entryDescriptions)
          """
      }
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the pubDate refresh scoring pass to suspend before sort switch." }
    )

    viewModel.currentSortMethod = .recommendationScore
    #expect(
      viewModel.recommendationDisplay == .computing,
      """
      Expected same-episode pubDate changes to invalidate cached recommendation \
      scores while the refresh is in flight.
      actual: \(viewModel.recommendationDisplay)
      """
    )

    fakeRepo.releaseEmbeddingsGate()
  }
}
