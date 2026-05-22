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

      // markFinished is a candidate-gate transition; it doesn't bump `scoringRevision`.
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

  @Test("rec-sort picks up a newly-embedded candidate without waiting on scoringRevision")
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

      // Adding an embedded candidate doesn't bump `scoringRevision`; the view
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

  @Test("toggling to rec sort shows .computingRecommendations until scoring lands")
  func togglingToRecSortShowsComputingRecommendations() async throws {
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
      // shows "Computing recommendations…" while the pass is in flight.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .computingRecommendations },
        { @MainActor in
          """
          Expected .computingRecommendations while the on-demand scoring pass \
          is stranded; got \(viewModel.loadingState).
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

  @Test("a scoring pass whose candidate set changed mid-flight is cancelled, not hydrated")
  func staleMidFlightScoringPassIsCancelledNotHydrated() async throws {
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
    // Quiesce setup-driven rebuilds so the gate below catches the scoring pass
    // this test strands, not a stray Up Next rebuild.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    fakeRecommendationRepo.clearAllCalls()

    let allTargetIDs = Set(targets.map(\.id))
    let finishedID = targets[2].id
    let liveIDs = Set(targets.prefix(2).map(\.id))

    let viewModel = EpisodesListViewModel(
      title: "RecStaleMidFlight",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    // Strand the initial scoring pass on its embeddings read so a
    // candidate-set change can land while it is in flight.
    fakeRecommendationRepo.armEmbeddingsGate(matching: allTargetIDs)

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { fakeRecommendationRepo.isEmbeddingsGateSuspended },
        { "Expected the initial scoring pass to suspend on the gated embeddings read." }
      )

      // Target 2 leaves the candidate pool while the first pass is stranded.
      // The candidate observation re-emits {Target 0, Target 1}, which cancels
      // the stranded pass and starts a fresh one for the live set.
      _ = try await repo.markFinished(finishedID)
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == liveIDs
        },
        { @MainActor in
          """
          Expected the restarted pass to surface only the live candidates.
          Expected: \(liveIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      // Release the stranded pass: cancelled, it resumes past the embeddings
      // read and bails. Poll a window to confirm it never publishes its stale
      // {Target 0, 1, 2} set — hydration filters by score-map IDs alone, so a
      // stale publish would surface the finished episode in the candidate list.
      fakeRecommendationRepo.releaseEmbeddingsGate()
      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor in
            viewModel.episodeList.filteredEntries.compactMap(\.episodeID).contains(finishedID)
          },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: a scoring pass stranded mid-flight published its stale \
          candidate set — the finished episode \(finishedID) surfaced in the \
          rec-sorted candidate list. A pass whose candidate set changed while \
          it ran must be cancelled, not hydrated.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      #expect(
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == liveIDs,
        """
        Expected the rec-sorted list to still hold only the live candidates \
        after the stale pass bailed.
        Expected: \(liveIDs)
        Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
        """
      )
    }
  }

  @Test("re-entering rec sort under a new search shows computing, not stale rows")
  func reEnteringRecSortUnderNewSearchShowsComputingNotStaleRows() async throws {
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

    _ = try await RecommendationHelpers.startAndWaitForScores(for: alphas + betas)
    // Quiesce setup-driven rebuilds so the gate below catches the re-entry's
    // own scoring pass, not a stray Up Next rebuild.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    let alphaIDs = Set(alphas.map(\.id))
    let betaIDs = Set(betas.map(\.id))

    let viewModel = EpisodesListViewModel(
      title: "RecReEnterNewSearch",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      // Score the rec sort under the empty search: all four targets land.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
            == alphaIDs.union(betaIDs)
        },
        { @MainActor in
          """
          Expected all four targets scored under the empty search first.
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      // Leave rec sort, then change the search text while on a standard sort.
      viewModel.currentSortMethod = .newestFirst
      let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
      let pendingBeforeSearch = fakeSleeper.pendingCount()
      viewModel.filterDebouncer.currentValue = "Betacand"
      try await fakeSleeper.waitForSleepRequests(count: pendingBeforeSearch + 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == betaIDs
        },
        { @MainActor in
          "Expected the standard sort to narrow to Betacand, got \(viewModel.loadingState)."
        }
      )

      // Strand the re-entry's scoring pass so the computing window is stable.
      fakeRecommendationRepo.armEmbeddingsGate(matching: betaIDs)

      // Re-enter rec sort. The retained score map was computed for the empty
      // search; it must NOT hydrate as loaded under the new search — that
      // would surface Alphacand rows that don't match "Betacand". The honest
      // state is .computingRecommendations until the fresh pass lands.
      viewModel.currentSortMethod = .recommendationScore
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .computingRecommendations },
        { @MainActor in
          """
          Expected .computingRecommendations on rec-sort re-entry under the new \
          search; a stale retained score map hydrated as loaded instead.
          State: \(viewModel.loadingState)
          Entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
      #expect(
        Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          .isDisjoint(with: alphaIDs),
        """
        Stale Alphacand rows surfaced under the "Betacand" search while the \
        on-demand scoring pass was still computing.
        Entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
        """
      )

      // Releasing the pass lets the correct, search-scoped list load.
      fakeRecommendationRepo.releaseEmbeddingsGate()
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          guard case .loaded = viewModel.loadingState else { return false }
          return Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == betaIDs
        },
        { @MainActor in
          """
          Expected the rec-sorted list to settle to the Betacand candidates.
          Expected: \(betaIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }

  @Test("changing the search on rec sort tears down the old search's hydration")
  func searchChangeOnRecSortTearsDownStaleHydration() async throws {
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

    _ = try await RecommendationHelpers.startAndWaitForScores(for: alphas + betas)
    // Quiesce setup-driven rebuilds so the gate below catches the search
    // change's own scoring pass, not a stray Up Next rebuild.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    let alphaIDs = Set(alphas.map(\.id))
    let betaIDs = Set(betas.map(\.id))

    let viewModel = EpisodesListViewModel(
      title: "RecSearchChangeStaleHydration",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      // Score the rec sort under the empty search: all four targets land and
      // the hydration observation tracks the Alphacand + Betacand rows.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
              == alphaIDs.union(betaIDs)
        },
        { @MainActor in
          """
          Expected all four targets scored under the empty search first.
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      // Strand the search change's scoring pass so the hydration race has a
      // stable window: while it is gated, the only task that can publish a
      // loaded list is the empty-search hydration — if it is still alive.
      fakeRecommendationRepo.armEmbeddingsGate(matching: betaIDs)

      // Narrow the search to "Betacand" while staying on rec sort. This
      // restarts the recommendation observation; the Alphacand-tracking
      // hydration from the empty search must be torn down, not left running.
      let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
      let pendingBeforeSearch = fakeSleeper.pendingCount()
      viewModel.filterDebouncer.currentValue = "Betacand"
      try await fakeSleeper.waitForSleepRequests(count: pendingBeforeSearch + 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .computingRecommendations },
        { @MainActor in
          """
          Expected .computingRecommendations while the search change's scoring \
          pass is stranded; got \(viewModel.loadingState).
          """
        }
      )

      // A background write touches an Alphacand row — exactly the rows the
      // empty-search hydration observation tracked (it filters by score-map ID
      // alone, no text search). A surviving observation re-emits and publishes
      // a loaded list of stale Alphacand rows under the new "Betacand" search.
      let staleID = try #require(alphas.first?.id)
      _ = try await appDB.db.write { db in
        try Episode.withID(staleID)
          .updateAll(db, Episode.Columns.title.set(to: "Mutated Alphacand"))
      }

      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor in viewModel.loadingState == .loaded },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: changing the search on rec sort left the old search's \
          hydration observation running. A background write to an Alphacand \
          row drove it to publish a loaded list while the new search's scoring \
          pass was still computing.
          State: \(viewModel.loadingState)
          Entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      // Releasing the pass lets the correct, search-scoped list load.
      fakeRecommendationRepo.releaseEmbeddingsGate()
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          guard case .loaded = viewModel.loadingState else { return false }
          return Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == betaIDs
        },
        { @MainActor in
          """
          Expected the rec-sorted list to settle to the Betacand candidates.
          Expected: \(betaIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }
}
