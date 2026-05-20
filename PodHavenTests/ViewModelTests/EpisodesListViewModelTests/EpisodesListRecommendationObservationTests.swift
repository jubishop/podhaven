// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation observation tests", .container)
@MainActor final class EpisodesListRecommendationObservationTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("rec-sort honors live filterText changes (rescore on text search)")
  func recommendationSortRespectsLiveFilterTextChanges() async throws {
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

    let (_, alphas) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target Alphacand",
      podcastDescription: "Target Alphacand",
      episodeDescriptions: ["Target Alphacand 0", "Target Alphacand 1"]
    )
    try await RecommendationHelpers.embedEpisodes(alphas, embeddable: embeddable)

    let (_, betas) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target Betacand",
      podcastDescription: "Target Betacand",
      episodeDescriptions: ["Target Betacand 0", "Target Betacand 1"]
    )
    try await RecommendationHelpers.embedEpisodes(betas, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(
      for: alphas + betas
    )

    let viewModel = EpisodesListViewModel(
      title: "RecSearch",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      let allIDs = Set((alphas + betas).map(\.id))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == allIDs
        },
        { @MainActor in
          """
          Expected all four candidates surfaced under rec sort first.
          Expected: \(allIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      viewModel.filterDebouncer.currentValue = "Alphacand"
      let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
      try await fakeSleeper.waitForSleepRequests(count: 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))

      let alphaIDs = Set(alphas.map(\.id))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == alphaIDs
        },
        { @MainActor in
          """
          Expected rec-sort to narrow to Alphacand candidates after search; \
          stale top-IDs without rescore would still surface Betacand rows.
          Expected: \(alphaIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }

  @Test("rec-sort drops rows that stop matching the base SQL filter")
  func recommendationSortHydrationRespectsBaseFilterOnRowMutation() async throws {
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

    let viewModel = EpisodesListViewModel(
      title: "RecBaseFilter",
      filter: Episode.unfinished
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      let allIDs = Set(targets.map(\.id))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          let visible = Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          return visible.isSuperset(of: allIDs)
        },
        { @MainActor in
          """
          Expected both targets visible under rec sort before mutating finish state.
          Expected superset of: \(allIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      // markFinished is a candidate-gate transition; it doesn't bump `contextRevision`.
      let finishedID = targets[0].id
      _ = try await repo.markFinished(finishedID)

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          !viewModel.episodeList.filteredEntries.compactMap(\.episodeID).contains(finishedID)
        },
        { @MainActor in
          """
          Expected finished episode \(finishedID) to disappear from rec-sorted \
          unfinished list; stale top-IDs without base-filter ANDing still surface it.
          Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )
    }
  }

  @Test("rec-sort picks up a newly-embedded candidate without waiting on contextRevision")
  func recommendationSortSnapsInNewlyEmbeddedCandidate() async throws {
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

    let (signalPodcast, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let (_, initialTargets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Target Initial",
      podcastDescription: "Target Initial",
      episodeDescriptions: ["Target 0"]
    )
    try await RecommendationHelpers.embedEpisodes(initialTargets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: initialTargets)

    let viewModel = EpisodesListViewModel(
      title: "RecSnapIn",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      let initialIDs = Set(initialTargets.map(\.id))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == initialIDs
        },
        { @MainActor in
          """
          Expected initial target visible under rec sort before adding a new candidate.
          Expected: \(initialIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      // Adding an embedded candidate doesn't bump `contextRevision`; the view
      // model has to pick it up from the candidate-set observation.
      let newCandidates = try await RecommendationHelpers.addEpisodes(
        to: signalPodcast,
        count: 1,
        episodeDescriptions: ["Target Late"],
        pubDateOffset: { _ in -3600 }
      )
      try await RecommendationHelpers.embedEpisodes(newCandidates, embeddable: embeddable)
      let lateID = try #require(newCandidates.first?.id)

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.compactMap(\.episodeID).contains(lateID)
        },
        { @MainActor in
          """
          Expected newly-embedded candidate \(lateID) to snap into rec-sorted list \
          via candidate-set observation; got \
          \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )
    }
  }

  @Test("rec-sort hydration observes visible episode title changes")
  func recommendationSortHydrationObservesVisibleEpisodeTitleChanges() async throws {
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

    let targetID = try #require(targets.first?.id)
    let viewModel = EpisodesListViewModel(
      title: "RecTitleHydration",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.compactMap(\.episodeID).contains(targetID)
        },
        { @MainActor in
          """
          Expected target \(targetID) to be visible before title mutation; got \
          \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)).
          """
        }
      )

      let updatedTitle = "Retitled Target Episode"
      _ = try await appDB.db.write { db in
        try Episode.withID(targetID).updateAll(db, Episode.Columns.title.set(to: updatedTitle))
      }

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries[id: targetID]?.title == updatedTitle
        },
        { @MainActor in
          """
          Expected hydrated rec-sort row \(targetID) to observe updated title \
          '\(updatedTitle)'; got \
          \(String(describing: viewModel.episodeList.filteredEntries[id: targetID]?.title)).
          """
        }
      )
    }
  }

  @Test("toggling between non-rec and rec sorts doesn't restart the candidate observation")
  func togglingSortPreservesCandidateObservation() async throws {
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
      title: "ToggleStability",
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
      _ = try fakeObservatory.expectCalls(methodName: "embeddedCandidateEpisodes", count: 1)

      // From here on, any new candidate-observation start would show up as
      // another embeddedCandidateEpisodes call — that's the regression we
      // want to prevent.
      fakeObservatory.clearAllCalls()

      viewModel.currentSortMethod = .recommendationScore
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

      try fakeObservatory.expectNoCall(methodName: "embeddedCandidateEpisodes")
    }
  }

  @Test("candidate observation runs in background even when sort is non-rec")
  func candidateObservationRunsOnNonRecSort() async throws {
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
      title: "NonRecBackgroundObs",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          fakeObservatory.allCallsInOrder.contains { $0.methodName == "embeddedCandidateEpisodes" }
        },
        { @MainActor in
          """
          Expected the candidate observation to call embeddedCandidateEpisodes \
          even on a non-rec sort, but it never did.
          """
        }
      )
    }
  }

  @Test("toggling to rec-sort after background scoring lands skips .computingRecommendations")
  func togglingToRecAfterBackgroundScoringSkipsComputingState() async throws {
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

    // Pre-warm the engine cache so the view model's background scoring is
    // CPU-bound rather than waiting on a cold cache rebuild.
    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)

    let viewModel = EpisodesListViewModel(
      title: "WarmToggle",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    let recorder = LoadingStateRecorder(viewModel: viewModel)

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in "Expected non-rec sort to settle, got \(viewModel.loadingState)." }
      )

      // Yield generously so the background candidate observation has time
      // to land its first scoring pass against the pre-warmed engine
      // cache. Each hop unblocks the chain: candidate emission →
      // kickRecommendationFetch → fetchAndApplyRecommendationScores →
      // recommendationScoresState = .loaded.
      for _ in 0..<200 { await Task.yield() }

      let targetIDs = Set(targets.map(\.id))
      viewModel.currentSortMethod = .recommendationScore
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          guard case .loaded = viewModel.loadingState else { return false }
          return Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected rec-sort entries to settle after toggle.
          State: \(viewModel.loadingState)
          Entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      #expect(
        !recorder.values.contains(.computingRecommendations),
        """
        Warm background scoring should have populated top IDs before the toggle, \
        letting startDisplayObservation skip .computingRecommendations. Recorded \
        loadingState transitions: \(recorder.values)
        """
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

    // Re-appear (tab switch back) with the candidate set and contextRevision
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

  @Test("a trailing-coalesced rescan scores the latest candidate set, not a stale captured one")
  func trailingCoalescedRescanScoresLatestCandidates() async throws {
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
      count: 3,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1", "Target 2"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    // Quiesce setup-driven rebuilds so the only sleeper-gated work left is the
    // trailing debounce this test orchestrates.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
    fakeRecommendationRepo.clearAllCalls()

    let allTargetIDs = Set(targets.map(\.id))
    // The candidate set the trailing debounce captures mid-pass: {Target 0,
    // Target 1}, after Target 2 leaves the pool but before Target 1 does.
    let staleCandidateIDs = Set(targets.prefix(2).map(\.id))
    let latestCandidateIDs = Set([targets[0].id])

    let viewModel = EpisodesListViewModel(
      title: "RecTrailingCoalesce",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    // Strand the first scoring pass mid-flight so candidate-set churn can
    // interleave with an in-flight pass.
    fakeRecommendationRepo.armEmbeddingsGate(matching: allTargetIDs)

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { fakeRecommendationRepo.isEmbeddingsGateSuspended },
        { "Expected the first scoring pass to suspend on the gated embeddings read." }
      )

      // Churn #1 lands while the pass is in flight: Target 2 leaves the
      // candidate pool, so the kick is coalesced — arming the trailing
      // debounce with the {Target 0, Target 1} snapshot. Two debounces arm:
      // the engine's re-rank and the view model's trailing rescan.
      let pendingBeforeChurn = fakeSleeper.pendingCount()
      _ = try await repo.markFinished(targets[2].id)
      try await fakeSleeper.waitForSleepRequests(count: pendingBeforeChurn + 2)

      // Release the stranded pass and let it fully land, freeing the slot.
      fakeRecommendationRepo.releaseEmbeddingsGate()
      try await Wait.until(
        priority: .userInitiated,
        { fakeRecommendationRepo.didEmbeddingsGateComplete },
        { "Expected the stranded scoring pass to complete once the gate released." }
      )
      for _ in 0..<200 { await Task.yield() }

      // Churn #2 lands with the slot free: Target 1 leaves the pool, so this
      // kick runs immediately via the direct path and scores {Target 0}. The
      // trailing debounce still holds the older {Target 0, Target 1} snapshot.
      _ = try await repo.markFinished(targets[1].id)
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
            matching: latestCandidateIDs
          ) >= 1
        },
        { "Expected the direct-path rescan to score the latest {Target 0} candidate set." }
      )
      for _ in 0..<200 { await Task.yield() }

      // Fire the trailing debounce. It must rescan the latest observed
      // candidates ({Target 0} — already scored, so the kick is skipped),
      // never the stale {Target 0, Target 1} snapshot captured when it armed.
      await RecommendationScoringTestHelpers.drainRecommendationSleeper()
      for _ in 0..<200 { await Task.yield() }

      let staleRescans = RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
        matching: staleCandidateIDs
      )
      #expect(
        staleRescans == 0,
        """
        The trailing-coalesced rescan scored a stale candidate snapshot: \
        \(staleRescans) embeddings(for:) call(s) for {Target 0, Target 1} after \
        the candidate set had already moved on to {Target 0}. The debounce must \
        rescan the latest observed candidates, not the set captured when it armed.
        """
      )
    }
  }
}
