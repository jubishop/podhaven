// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation stale pass tests", .container)
@MainActor final class EpisodesListRecommendationStalePassTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.repo) private var repo

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
