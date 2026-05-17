// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Regression tests for the recommendation-score fan-out OOM (issue #274).
@Suite("of PodcastDetailViewModel recommendation scoring coalescing tests", .container)
@MainActor final class RecommendationScoringTests {
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
      count <= 5,
      """
      Expected per-VM coalescing to bound the scoring fan-out, but \(count) \
      scoring passes fired for the same candidate set during a burst of 50 \
      $contextRevision bumps.
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
