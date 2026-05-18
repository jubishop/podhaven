// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of PodcastDetailViewModel recommendation scoring coalescing tests", .container)
@MainActor final class RecommendationScoringTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeperFactory

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  private var fakeSleeper: FakeSleeper { sleeperFactory as! FakeSleeper }

  // MARK: - Background prewarming preserved

  @Test(
    "background scoring on .newestFirst caches scores so a later switch to .recommendationScore applies them"
  )
  func backgroundPrewarmingAppliesWithoutRefetch() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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
      { [self] in
        await MainActor.run { scopedEmbeddingsCallCount(matching: targetIDs) >= 1 }
      },
      { [self] in
        await MainActor.run {
          """
          Expected background prewarming to fetch embeddings while on .newestFirst.
          calls: \(scopedEmbeddingsCallCount(matching: targetIDs))
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

  // MARK: - Burst coalescing

  @Test(
    "a burst of $contextRevision bumps must coalesce into a bounded number of scoring passes (≤ 2)"
  )
  func burstContextRevisionBumpsCoalesce() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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
      { [self] in
        await MainActor.run { scopedEmbeddingsCallCount(matching: targetIDs) >= 1 }
      },
      { @MainActor in
        "Expected at least one initial scoring pass before the burst."
      }
    )
    fakeRecommendationRepo.clearAllCalls()

    for _ in 0..<50 {
      recommendationEngine.$contextRevision.update { $0 += 1 }
    }

    for _ in 0..<80 {
      await fakeSleeper.advanceTime(by: .milliseconds(200))
      await Task.yield()
    }

    let count = scopedEmbeddingsCallCount(matching: targetIDs)
    #expect(
      count <= 2,
      """
      Expected per-VM coalescing to bound the scoring fan-out, but \(count) \
      scoring passes fired for the same candidate set during a burst of 50 \
      $contextRevision bumps. The contract is one trailing pass per debounce \
      window, plus at most one runningDirty rerun.
      """
    )
  }

  // MARK: - Latest-state-only publish

  @Test(
    "a scoring pass against a stale list-identity must not overwrite scores from a newer pass"
  )
  func staleListIdentityMustNotOverwriteNewerScores() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    let fakeRepo = fakeRecommendationRepo
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

  // MARK: - Snapshot-validated cache apply on sort-switch

  @Test(
    "switching to .recommendationScore while the cached scores are stale must not hide newly-arrived episodes during the refresh window"
  )
  func staleCacheOnSortSwitchDoesNotHideNewEpisodes() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: initialIDs)
    recommendationEngine.$contextRevision.update { $0 += 1 }
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the post-bump scoring pass to suspend before list change." }
    )

    try await repo.updateSeriesFromFeed(
      podcastSeries: savedSeries,
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(
          guid: GUID("target-4"),
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

    viewModel.currentSortMethod = .recommendationScore

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in viewModel.episodeList.filteredEntries.count == 5 },
      { @MainActor in
        """
        Applying the stale four-ID cache filtered out the newly-arrived \
        fifth episode. Expected snapshot validation to keep all five visible.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "switching to .recommendationScore while same-episode cached scores have stale pubDates keeps the refresh visible"
  )
  func stalePubDateCacheOnSortSwitchShowsRefresh() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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
      { [self] in
        await MainActor.run { scopedEmbeddingsCallCount(matching: targetIDs) >= 1 }
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

  @Test(
    "recommendationDisplay reflects an in-flight refresh while rec-sort is active and clears once scores apply"
  )
  func recommendationDisplayToggles() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

  // MARK: - Hot-cache bootstrap preserved

  @Test(
    "PodcastDetailViewModel opened against a hot engine cache scores without a subsequent $contextRevision bump"
  )
  func podcastDetailHotCacheBootstrapScoresImmediately() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

    let (targetPodcast, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 3,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2"]
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

    viewModel.currentSortMethod = .recommendationScore

    let expectedIDs = Set(candidateEpisodes.map(\.id))
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == expectedIDs
      },
      { @MainActor in
        """
        Expected initial bootstrap scoring to populate the rec-score sort even \
        when the engine cache is already hot and no further \
        $contextRevision bump arrives.
        filteredEntries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel surfaces .computing on displayedScore while a fetch is in flight and replaces it on completion"
  )
  func episodeDetailScoringIndicatorToggles() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set([targetEpisodeID]))

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .computing = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected displayedScore to be .computing while the fetch is in flight.
        actual: \(String(describing: viewModel.displayedScore))
        """
      }
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected scoring fetch to suspend on the gated embeddings call." }
    )

    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        if case .recommendation = viewModel.displayedScore { return true }
        return false
      },
      { @MainActor in
        """
        Expected displayedScore to settle on .recommendation once the fetch completes.
        actual: \(String(describing: viewModel.displayedScore))
        """
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel observes the first contextRevision emitted immediately after recommendation observation starts"
  )
  func episodeDetailDoesNotDropFirstContextRevisionAfterObservationStarts() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    let fakeRepo = fakeRecommendationRepo
    let targetIDs = Set([targetEpisodeID])
    fakeRepo.armEmbeddingsGate(matching: targetIDs)

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    recommendationEngine.$contextRevision.update { $0 += 1 }

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected bootstrap scoring to suspend before releasing it." }
    )

    fakeRecommendationRepo.clearAllCalls()
    fakeRepo.releaseEmbeddingsGate()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { [self] in
        await MainActor.run { scopedEmbeddingsCallCount(matching: targetIDs) >= 1 }
      },
      { [self] in
        await MainActor.run {
          """
          Expected the first post-start contextRevision to schedule a trailing \
          refresh after the gated bootstrap pass completed.
          calls: \(scopedEmbeddingsCallCount(matching: targetIDs))
          displayedScore: \(String(describing: viewModel.displayedScore))
          """
        }
      }
    )
  }

  @Test(
    "EpisodeDetailViewModel drops a stale bootstrap recommendation if a newer context refresh publishes first"
  )
  func episodeDetailStaleContextFetchDoesNotOverwriteNewerScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    Container.shared.userSettings().$podcastAffinityWeight.new(0)

    let embeddable = MutableScriptedEmbeddable { text in
      if text.contains("Anchor") { return [0, 1, 0] }
      if text.contains("Old Signal") { return [1, 0, 0] }
      if text.contains("Fresh Signal") { return [0, 1, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, oldSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Old Signal",
      podcastDescription: "Old Signal",
      episodeDescriptions: Array(repeating: "Old Signal", count: 3),
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(oldSignals, embeddable: embeddable.scripted)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: oldSignals)

    let (_, candidateEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target", "Anchor"],
      pubDateOffset: { index in index == 0 ? -90 * 86400 : 0 }
    )
    try await RecommendationHelpers.embedEpisodes(
      candidateEpisodes,
      embeddable: embeddable.scripted
    )
    let targetEpisode = try #require(candidateEpisodes.first)
    let targetID = targetEpisode.id
    _ = try await RecommendationHelpers.startAndWaitForScores(for: candidateEpisodes)

    let podcastEpisode = try #require(try await repo.podcastEpisode(targetID))
    let fakeRepo = fakeRecommendationRepo
    fakeRepo.armEmbeddingsGate(matching: Set([targetID]))

    let viewModel = EpisodeDetailViewModel(episode: DisplayedEpisode(podcastEpisode))
    try await viewModel.performAppear()

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the bootstrap recommendation fetch to suspend." }
    )

    let (_, freshSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 12,
      podcastTitle: "Fresh Signal",
      podcastDescription: "Fresh Signal",
      episodeDescriptions: Array(repeating: "Fresh Signal", count: 12),
      ratings: Array(repeating: .loved, count: 12)
    )
    try await RecommendationHelpers.embedEpisodes(freshSignals, embeddable: embeddable.scripted)

    let freshScore: Float = try await RecommendationHelpers.waitAdvancing {
      await MainActor.run {
        guard case .recommendation(let score) = viewModel.displayedScore else {
          return nil
        }
        return score.value
      }
    }

    fakeRepo.releaseEmbeddingsGate()
    try await Wait.until(
      priority: .userInitiated,
      { fakeRepo.didEmbeddingsGateComplete },
      { "Expected the stale bootstrap embeddings call to complete after release." }
    )
    await Task.yield()

    guard case .recommendation(let finalScore) = viewModel.displayedScore else {
      Issue.record(
        "Expected final displayedScore to remain a recommendation, got \(String(describing: viewModel.displayedScore))"
      )
      return
    }
    #expect(
      abs(finalScore.value - freshScore) < 0.001,
      """
      The stale bootstrap fetch overwrote the newer context-refresh score.
      freshScore: \(freshScore)
      finalScore: \(finalScore.value)
      """
    )
  }

  @Test(
    "EpisodeDetailViewModel opened against a hot engine cache surfaces a displayedScore without a subsequent $contextRevision bump"
  )
  func episodeDetailHotCacheBootstrapScoresImmediately() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

  // MARK: - Active rec sort live-updates after coalesced refresh

  @Test(
    "while .recommendationScore is active, a $contextRevision bump triggers a coalesced refresh that updates the visible order"
  )
  func activeRecSortLiveUpdatesAfterCoalescedRefresh() async throws {
    let embeddable = MutableScriptedEmbeddable(
      initial: { text in
        if text.contains("Filler") { return [0, 0, 1] }
        if text.contains("Signal") { return [1, 0, 0] }
        if text.contains("Target 0") { return [0.2, 0.98, 0] }
        if text.contains("Target 1") { return [0.4, 0.917, 0] }
        if text.contains("Target 2") { return [0.6, 0.8, 0] }
        if text.contains("Target 3") { return [0.8, 0.6, 0] }
        if text.contains("Target") { return [0, 1, 0] }
        return [0, 0, 1]
      }
    )
    try await primeEngine(with: embeddable.scripted)

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
      embeddable: embeddable.scripted
    )
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

    viewModel.currentSortMethod = .recommendationScore

    let initialOrder: [Episode.ID] = try await RecommendationHelpers.waitAdvancing {
      let order = await MainActor.run {
        viewModel.episodeList.filteredEntries.compactMap(\.episodeID)
      }
      return order.count == candidateEpisodes.count ? order : nil
    }

    embeddable.swap { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.8, 0.6, 0] }
      if text.contains("Target 1") { return [0.6, 0.8, 0] }
      if text.contains("Target 2") { return [0.4, 0.917, 0] }
      if text.contains("Target 3") { return [0.2, 0.98, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }
    try await RecommendationHelpers.embedEpisodes(
      candidateEpisodes,
      embeddable: embeddable.scripted
    )
    let refreshedScores = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )

    let expectedOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsScore = refreshedScores[lhs.id]?.value ?? 0
        let rhsScore = refreshedScores[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
        if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
          return lhs.mediaGUID.guid > rhs.mediaGUID.guid
        }
        return lhs.mediaGUID.mediaURL.rawValue.absoluteString
          > rhs.mediaGUID.mediaURL.rawValue.absoluteString
      }
      .map(\.id)
    try #require(
      initialOrder != expectedOrder,
      """
      Flipping the embedding script must produce a different rec-score order; \
      otherwise the test cannot observe the live-update.
      """
    )

    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { @MainActor in
        viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == expectedOrder
      },
      { @MainActor in
        """
        Expected coalesced refresh to publish the updated rec-score order.
        Expected: \(expectedOrder)
        Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
        """
      }
    )
  }

  // MARK: - Cached-snapshot fast path

  @Test(
    "a transition whose snapshot equals the cached snapshot must not trigger a redundant scoring pass"
  )
  func sameSnapshotTransitionSkipsRedundantCompute() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    for _ in 0..<10 {
      await fakeSleeper.advanceTime(by: .seconds(2))
      await Task.yield()
    }
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

    for _ in 0..<10 {
      await fakeSleeper.advanceTime(by: .seconds(2))
      await Task.yield()
    }

    let postTransitionCalls = scopedEmbeddingsCallCount(matching: targetIDs)
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

  // MARK: - Disappear cancels in-flight scoring

  @Test(
    "disappear cancels the in-flight immediate scoring task so its runningDirty rerun is dropped"
  )
  func disappearCancelsInflightScoringPass() async throws {
    let embeddable = scoringEmbeddable()
    try await primeEngine(with: embeddable)

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

    for _ in 0..<10 {
      await fakeSleeper.advanceTime(by: .seconds(2))
      await Task.yield()
    }

    let postDisappearCalls = scopedEmbeddingsCallCount(matching: targetIDs)
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

  // MARK: - Helpers

  private func scopedEmbeddingsCallCount(matching ids: Set<Episode.ID>) -> Int {
    fakeRecommendationRepo.calls(of: MethodCall<[Episode.ID]>.self)
      .filter { $0.methodName == "embeddings" && Set($0.parameters) == ids }
      .count
  }

  private func scoringEmbeddable() -> ScriptedEmbeddable {
    ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }
  }

  private func primeEngine(with embeddable: ScriptedEmbeddable) async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)
    _ = try await RecommendationHelpers.startAndWaitForScores(for: signals)
  }
}

// MARK: - MutableScriptedEmbeddable

private final class MutableScriptedEmbeddable: @unchecked Sendable {
  private let vectorFor = ThreadSafe<@Sendable (String) -> [Double]>({ _ in [0, 0, 1] })

  let scripted: ScriptedEmbeddable

  init(initial: @escaping @Sendable (String) -> [Double]) {
    vectorFor(initial)
    let vectorForBox = vectorFor
    scripted = ScriptedEmbeddable { text in
      vectorForBox()(text)
    }
  }

  func swap(_ next: @escaping @Sendable (String) -> [Double]) {
    vectorFor(next)
  }
}
