// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation lifecycle tests", .container)
@MainActor final class EpisodesListRecommendationLifecycleTests {
  @DynamicInjected(\.observatory) private var observatory

  @Test("recommendationScore sort starts the candidate observation; leaving it tears it down")
  func togglingRecSortStartsAndStopsCandidateObservation() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

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

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)

    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let targetIDs = Set(targets.map(\.id))

    let viewModel = EpisodesListViewModel(
      title: "ToggleOnDemand",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    fakeObservatory.clearAllCalls()

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in "Expected non-rec sort to settle, got \(viewModel.loadingState)." }
      )
      // A non-rec sort never starts the candidate observation.
      try fakeObservatory.expectNoCall(methodName: "embeddedCandidateEpisodes")

      viewModel.currentSortMethod = .recommendationScore
      // Observe the candidate-observation call itself: the stale newestFirst
      // list survives the toggle, so a list-contents check would pass before
      // the rec observation has even started.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          fakeObservatory.allCallsInOrder.contains {
            $0.methodName == "embeddedCandidateEpisodes"
          }
        },
        { @MainActor in "Expected rec sort to start the candidate observation." }
      )
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected rec-sort entries after toggle.
          Expected: \(targetIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
      // Selecting rec sort starts exactly one candidate observation on demand.
      _ = try fakeObservatory.expectCalls(methodName: "embeddedCandidateEpisodes", count: 1)

      viewModel.currentSortMethod = .newestFirst
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          "Expected non-rec sort to settle again, got \(viewModel.loadingState)."
        }
      )
      // Leaving rec sort tears the candidate observation down — the count stays
      // pinned at the single on-demand start; nothing keeps scanning after.
      _ = try fakeObservatory.expectCalls(methodName: "embeddedCandidateEpisodes", count: 1)
    }
  }

  @Test("non-rec sort never starts recommendation scoring work")
  func recommendationWorkDoesNotRunOnNonRecSort() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    let fakeObservatory = try #require(observatory as? FakeObservatory)
    fakeObservatory.clearAllCalls()

    let viewModel = EpisodesListViewModel(
      title: "NonRecNoScoring",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    try await withRunningObservationLoop(viewModel) {
      // Poll a window: while the sort stays non-rec, the candidate observation
      // that drives recommendation scoring must never start.
      do {
        try await Wait.until(
          maxAttempts: 100,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor in
            fakeObservatory.allCallsInOrder.contains {
              $0.methodName == "embeddedCandidateEpisodes"
            }
          },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: a non-rec sort started the candidate observation \
          (embeddedCandidateEpisodes). Recommendation scoring must only run on \
          demand, while the recommendationScore sort is selected.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      // The standard sort still loads its list — the view isn't broken, the
      // recommendation work simply never started.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in "Expected non-rec sort to settle, got \(viewModel.loadingState)." }
      )
      try fakeObservatory.expectNoCall(methodName: "embeddedCandidateEpisodes")
    }
  }

  @Test("toggling to rec sort shows .loading until scoring lands")
  func togglingToRecSortShowsLoading() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

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

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    // Quiesce setup-driven rebuilds so the gate below catches the toggle's
    // scoring pass, not a stray Up Next rebuild.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    let targetIDs = Set(targets.map(\.id))

    let viewModel = EpisodesListViewModel(
      title: "ColdToggle",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in "Expected non-rec sort to settle, got \(viewModel.loadingState)." }
      )

      // Strand the scoring pass the toggle kicks so the computing state is a
      // stable, observable window rather than a transient flash.
      fakeRecommendationRepo.armEmbeddingsGate(matching: targetIDs)

      viewModel.currentSortMethod = .recommendationScore

      // On-demand scoring runs no background pass, so toggling to rec sort
      // shows "Loading…" while the pass is in flight.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .loading },
        { @MainActor in
          """
          Expected .loading while the on-demand scoring pass is stranded; \
          got \(viewModel.loadingState).
          """
        }
      )

      // Releasing the pass lets scoring land and the rec-sorted list load.
      fakeRecommendationRepo.releaseEmbeddingsGate()
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          guard case .loaded = viewModel.loadingState else { return false }
          return Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected the rec-sorted list to load once scoring landed.
          State: \(viewModel.loadingState)
          Entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }

  @Test("re-appearing with an unchanged candidate set skips a redundant scoring pass")
  func reappearWithUnchangedCandidatesSkipsRescore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

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

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)

    let targetIDs = Set(targets.map(\.id))
    let viewModel = EpisodesListViewModel(
      title: "RecReappear",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    // First appear: let the initial scoring pass land and surface both targets.
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected the initial scoring pass to surface both targets under rec sort.
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
    // withRunningObservationLoop's teardown already called viewModel.disappear()
    // — the tab switch away from the Episodes list.

    await RecommendationScoringTestHelpers.drainRecommendationSleeper()
    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    fakeRecommendationRepo.clearAllCalls()

    // Re-appear (tab switch back) with the candidate set and scoringRevision
    // unchanged. The scores computed before the switch are still valid, so no
    // full-library scoring pass should run.
    try await withRunningObservationLoop(viewModel) {
      for _ in 0..<200 { await Task.yield() }
      await RecommendationScoringTestHelpers.drainRecommendationSleeper()

      let rescans = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
        matching: targetIDs
      )
      #expect(
        rescans == 0,
        """
        Re-appearing on the Episodes tab with an unchanged candidate set re-ran a \
        full-library scoring pass: \(rescans) embeddings(for:) call(s) for the \
        candidate IDs. A completed score should survive a tab switch.
        """
      )
    }
  }

  @Test("re-appearing after a podcastAffinityWeight change rescores the candidate set")
  func reappearAfterAffinityWeightChangeRescores() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)
    // A podcastAffinityWeight change also rebuilds the Up Next set, and that
    // pass reads embeddings for the same candidate IDs. Disabling it leaves the
    // view model's own rescan as the only embeddings(for:) read to assert on.
    Container.shared.userSettings().$maxRecommendedEpisodesInUpNext.new(0)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

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

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)

    let targetIDs = Set(targets.map(\.id))
    let viewModel = EpisodesListViewModel(
      title: "RecAffinityReappear",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    // First appear: let the initial scoring pass land and surface both targets.
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected the initial scoring pass to surface both targets under rec sort.
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
    // withRunningObservationLoop's teardown already called viewModel.disappear()
    // — the tab switch away from the Episodes list.

    await RecommendationScoringTestHelpers.drainRecommendationSleeper()
    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    fakeRecommendationRepo.clearAllCalls()

    // The affinity slider moves while the user is away on the Settings screen.
    // podcastAffinityWeight feeds scoreEpisodes live, so the score retained
    // across disappear() is now stale even though the candidate set is unchanged.
    Container.shared.userSettings().$podcastAffinityWeight.new(0.8)
    await RecommendationScoringTestHelpers.drainRecommendationSleeper()

    // Re-appear (tab switch back) with the candidate set unchanged. The retained
    // key must not suppress the rescore — the weight changed the scoring inputs.
    try await withRunningObservationLoop(viewModel) {
      for _ in 0..<200 { await Task.yield() }
      await RecommendationScoringTestHelpers.drainRecommendationSleeper()

      let rescans = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
        matching: targetIDs
      )
      #expect(
        rescans >= 1,
        """
        Re-appearing on the Episodes tab after a podcastAffinityWeight change \
        skipped rescoring: \(rescans) embeddings(for:) call(s) for the candidate \
        IDs. podcastAffinityWeight feeds scoreEpisodes, so the score retained \
        across the tab switch is stale and must be recomputed.
        """
      )
    }
  }
}
