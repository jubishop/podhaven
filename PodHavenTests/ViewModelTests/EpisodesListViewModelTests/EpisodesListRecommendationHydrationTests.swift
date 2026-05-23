// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation hydration tests", .container)
@MainActor final class EpisodesListRecommendationHydrationTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

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

  @Test("rec-sort removes the onDeck candidate without waiting for a playback DB tick")
  func recommendationSortRemovesOnDeckCandidate() async throws {
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

    let (targetPodcast, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)

    let viewModel = EpisodesListViewModel(
      title: "RecOnDeck",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      let allIDs = Set(targets.map(\.id))
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == allIDs
        },
        { @MainActor in
          """
          Expected both targets visible before selecting onDeck.
          Expected: \(allIDs)
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )

      let onDeckEpisode = try #require(targets.first)
      let onDeckID = onDeckEpisode.id
      let remainingID = try #require(targets.dropFirst().first?.id)
      sharedState.$onDeck.new(
        OnDeck(from: PodcastEpisode(podcast: targetPodcast, episode: onDeckEpisode))
      )

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          let visibleIDs = Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          return visibleIDs == Set([remainingID])
        },
        { @MainActor in
          """
          Expected rec-sort to drop onDeck candidate \(onDeckID) before any \
          playback DB tick. Actual: \
          \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
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
}
