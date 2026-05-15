// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel tests", .container)
@MainActor final class EpisodesListViewModelTests {
  @DynamicInjected(\.repo) private var repo

  private var fakeRepo: FakeRepo { repo as! FakeRepo }
  private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  private struct InjectedRepoError: Error, Sendable {}

  @Test("selectedEpisodesTagIntersection collapses to common tags across selection")
  func selectedEpisodesTagIntersectionAcrossSelection() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: setup.episodes)

    // ep1 = {A, B}, ep2 = {B, C}, ep3 = {A, B, C} → common is {B}.
    select(viewModel, ids: [setup.ep1.id, setup.ep2.id, setup.ep3.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [setup.tagB.id])
    #expect(
      viewModel.selectedEpisodesTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test("selectedEpisodesTagIntersection collapses to empty when an untagged episode is selected")
  func selectedEpisodesTagIntersectionWithUntagged() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: setup.episodes)

    // Adding ep4 (no tags) drags the intersection to empty even though
    // ep1, ep3 share {A, B}; the union still reports every tag in play.
    select(viewModel, ids: [setup.ep1.id, setup.ep3.id, setup.ep4.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(
      viewModel.selectedEpisodesTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test(
    "selectedEpisodesTagIntersection and union are empty when only untagged episodes are selected"
  )
  func selectedEpisodesTagHelpersOnUntaggedOnly() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: setup.episodes)

    select(viewModel, ids: [setup.ep4.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection and union are empty when no episodes are selected")
  func selectedEpisodesTagHelpersOnEmptySelection() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: setup.episodes)

    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection equals selected episode's tags for a single selection")
  func selectedEpisodesTagIntersectionForSingleSelection() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: setup.episodes)

    select(viewModel, ids: [setup.ep2.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [setup.tagB.id, setup.tagC.id])
    #expect(viewModel.selectedEpisodesTagUnion == [setup.tagB.id, setup.tagC.id])
  }

  @Test("selectedPodcastEpisodes preserves user-visible selection order")
  func selectedPodcastEpisodesPreservesSelectionOrder() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    // Visible order is reversed from DB rowid order so the test fails if
    // `WHERE id IN (...)` row order leaks through `selectedPodcastEpisodes`.
    let reversed = IdentifiedArray(
      uniqueElements: [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id]
        .compactMap { id in
          setup.episodes.first { $0.id == id }
        }
    )
    viewModel.episodeList.allEntries = reversed
    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.id) == [
          setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id,
        ]
      },
      { @MainActor in
        "Expected reversed visible order before selecting; got \(viewModel.episodeList.filteredEntries.map(\.id))"
      }
    )

    select(viewModel, ids: [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id])

    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(
      podcastEpisodes.map(\.id) == [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id]
    )
  }

  @Test("recommendationScore is offered as a sort option")
  func recommendationScoreOfferedAsSortOption() async throws {
    let viewModel = EpisodesListViewModel(title: "RecOption")
    #expect(viewModel.allSortMethods.contains(.recommendationScore))
  }

  @Test("recommendationScore sort reorders cross-podcast episodes by score descending")
  func recommendationScoreSortReordersCrossPodcastEpisodes() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
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

    // Spread the four candidates across two podcasts so the test exercises
    // the cross-podcast scoring path: each row has to look up its own
    // podcastID for the engine's affinity/freshness inputs.
    let (_, podcastA) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target A",
      podcastDescription: "Target A",
      episodeDescriptions: ["Target 0", "Target 3"]
    )
    try await RecommendationHelpers.embedEpisodes(podcastA, embeddable: embeddable)

    let (_, podcastB) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target B",
      podcastDescription: "Target B",
      episodeDescriptions: ["Target 1", "Target 2"]
    )
    try await RecommendationHelpers.embedEpisodes(podcastB, embeddable: embeddable)

    let candidateEpisodes = podcastA + podcastB
    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )
    let expectedOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoreMap[lhs.id]?.value ?? 0
        let rhsScore = scoreMap[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.id > rhs.id
      }
      .map(\.id)
    let newestFirstOrder =
      candidateEpisodes
      .sorted { $0.pubDate > $1.pubDate }
      .map(\.id)
    try #require(
      expectedOrder != newestFirstOrder,
      "Rec-score order matched newestFirst; the test wouldn't prove the sort applied."
    )

    let viewModel = EpisodesListViewModel(
      title: "RecSort",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == expectedOrder
        },
        { @MainActor in
          """
          Expected episodes sorted by recommendation score across podcasts.
          Expected: \(expectedOrder)
          Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("toggling from newestFirst to recommendationScore reorders the list by score")
  func togglingFromNewestFirstToRecommendationScoreReordersByScore() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target 0") { return [0.2, 0.98, 0] }
      if text.contains("Target 1") { return [0.4, 0.917, 0] }
      if text.contains("Target 2") { return [0.6, 0.8, 0] }
      if text.contains("Target 3") { return [0.8, 0.6, 0] }
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

    // pubDate-desc and score-desc disagree by construction: the youngest
    // target is `Target 0` (lowest similarity), the oldest is `Target 3`
    // (highest similarity). That keeps the two assertions below disjoint.
    let pubDate0 = Date(timeIntervalSince1970: 4000)
    let pubDate1 = Date(timeIntervalSince1970: 3000)
    let pubDate2 = Date(timeIntervalSince1970: 2000)
    let pubDate3 = Date(timeIntervalSince1970: 1000)
    let (_, candidateEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 4,
        podcastTitle: "Target",
        podcastDescription: "Target",
        episodeDescriptions: ["Target 0", "Target 1", "Target 2", "Target 3"],
        pubDateOffset: { i in [pubDate0, pubDate1, pubDate2, pubDate3][i].timeIntervalSinceNow }
      )
    try await RecommendationHelpers.embedEpisodes(candidateEpisodes, embeddable: embeddable)

    let scoreMap = try await RecommendationHelpers.startAndWaitForScores(
      for: candidateEpisodes
    )
    let scoreOrder =
      candidateEpisodes
      .sorted { lhs, rhs in
        let lhsScore = scoreMap[lhs.id]?.value ?? 0
        let rhsScore = scoreMap[rhs.id]?.value ?? 0
        if lhsScore != rhsScore { return lhsScore > rhsScore }
        return lhs.id > rhs.id
      }
      .map(\.id)
    let pubDateOrder =
      candidateEpisodes
      .sorted { $0.pubDate > $1.pubDate }
      .map(\.id)
    try #require(
      scoreOrder != pubDateOrder,
      "Score order matched pubDate-desc; the toggle assertion wouldn't prove the sort changed."
    )

    let viewModel = EpisodesListViewModel(
      title: "ToggleTest",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .newestFirst

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == pubDateOrder
        },
        { @MainActor in
          """
          Expected initial newestFirst order.
          Expected: \(pubDateOrder)
          Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )

      viewModel.currentSortMethod = .recommendationScore

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.compactMap(\.episodeID) == scoreOrder
        },
        { @MainActor in
          """
          Expected list reordered by recommendation score after toggle.
          Expected: \(scoreOrder)
          Actual: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("recommendationScore sort honors the view-model's base filter")
  func recommendationScoreSortHonorsBaseFilter() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Included 0") { return [0.2, 0.98, 0] }
      if text.contains("Included 1") { return [0.6, 0.8, 0] }
      if text.contains("Excluded") { return [0.4, 0.917, 0] }
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

    // Two finished + two unfinished candidates. The view filters to
    // finished only, so the rec sort should never surface the unfinished
    // episodes — even if their scores would otherwise rank above the
    // finished ones (Excluded 0 / 1 score between Included 0 and 1).
    let (_, includedEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 2,
        podcastTitle: "Included",
        podcastDescription: "Included",
        episodeDescriptions: ["Included 0", "Included 1"],
        finished: [true, true]
      )
    try await RecommendationHelpers.embedEpisodes(includedEpisodes, embeddable: embeddable)

    let (_, excludedEpisodes) =
      try await RecommendationHelpers
      .createPodcastWithEpisodes(
        count: 2,
        podcastTitle: "Excluded",
        podcastDescription: "Excluded",
        episodeDescriptions: ["Excluded 0", "Excluded 1"],
        finished: [false, false]
      )
    try await RecommendationHelpers.embedEpisodes(excludedEpisodes, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(
      for: includedEpisodes + excludedEpisodes
    )

    let viewModel = EpisodesListViewModel(
      title: "FinishedOnly",
      filter: Episode.finished
    )
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          let ids = Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          return ids == Set(includedEpisodes.map(\.id))
        },
        { @MainActor in
          """
          Expected rec sort to surface only finished episodes.
          Expected ids: \(Set(includedEpisodes.map(\.id)))
          Actual ids: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("loadingState is .computingRecommendations during rec-sort cold start")
  func loadingStateIsComputingRecommendationsOnRecSortColdStart() async throws {
    let fakeRecRepo =
      Container.shared.recommendationRepo() as! FakeRecommendationRepo
    let gate = AsyncStream<Void>.makeStream()
    fakeRecRepo.candidateEpisodesScript([
      {
        var iterator = gate.stream.makeAsyncIterator()
        _ = await iterator.next()
        return []
      }
    ])

    let viewModel = EpisodesListViewModel(title: "RecLoadingState")
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .computingRecommendations },
        { @MainActor in
          """
          Expected .computingRecommendations while scoring is parked, got \
          \(viewModel.loadingState).
          """
        }
      )

      gate.continuation.yield()
      gate.continuation.finish()

      // Empty candidates produced an empty score map; once the version
      // bumps the loop restarts and `runRecommendationSortObservation`
      // takes the empty-`topIDs` path, clearing `allEntries`.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.episodeList.filteredEntries.isEmpty },
        { @MainActor in
          """
          Expected filteredEntries to be empty after empty scoring landed.
          """
        }
      )
    } catch {
      gate.continuation.finish()
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

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

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
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
      let fakeSleeper = Container.shared.sleeper() as! FakeSleeper
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
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
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

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
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
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
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

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
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
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("rec-sort reaches .ready when candidate fetch throws so the UI isn't stuck")
  func loadingStateReachesReadyWhenCandidateFetchThrows() async throws {
    let fakeRecRepo =
      Container.shared.recommendationRepo() as! FakeRecommendationRepo
    fakeRecRepo.candidateEpisodesScript([
      { throw TestError.simulatedFailure }
    ])

    let viewModel = EpisodesListViewModel(title: "RecFetchError")
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .ready },
        { @MainActor in
          """
          Expected .ready after candidate fetch threw so the UI can recover; \
          got \(viewModel.loadingState).
          """
        }
      )
      #expect(viewModel.episodeList.filteredEntries.isEmpty)
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("rec-sort doesn't loop refetching when scoring fails against a non-empty embedded set")
  func recommendationSortDoesNotRetryLoopOnPersistentFetchError() async throws {
    // Embed real candidates so the rec-sort observation emits a non-empty
    // row set; without embedded rows the diff check against the cleared
    // marker is trivially equal and the loop can't manifest.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Loop",
      podcastDescription: "Loop",
      episodeDescriptions: ["Loop 0", "Loop 1"]
    )
    try await RecommendationHelpers.embedEpisodes(episodes, embeddable: embeddable)

    let fakeRecRepo =
      Container.shared.recommendationRepo() as! FakeRecommendationRepo
    let throwing: @Sendable () async throws -> [CandidateEpisode] = {
      throw TestError.simulatedFailure
    }
    fakeRecRepo.candidateEpisodesScript(Array(repeating: throwing, count: 50))

    let viewModel = EpisodesListViewModel(
      title: "RecLoopGuard",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .ready },
        { @MainActor in
          """
          Expected .ready after the first failed candidate fetch landed; got \
          \(viewModel.loadingState).
          """
        }
      )

      // Under the bug, applyEmptyScores leaves lastScoredCandidateIDs = []
      // while the observation still emits the embedded row IDs, so the
      // version-bump-driven restart kicks another candidateEpisodes call,
      // throws again, bumps again, and never settles. This poll detects
      // any post-.ready retry; under the fix the count is pinned at 1.
      @Sendable func candidateCallCount() -> Int {
        fakeRecRepo.callsByType()
          .values
          .flatMap { $0 }
          .filter { $0.methodName == "candidateEpisodes" }
          .count
      }

      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { candidateCallCount() >= 2 },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: candidateEpisodes was retried after the first failure \
          (count=\(candidateCallCount())); persistent rec errors trigger a \
          refetch loop while the observed embedded row set stays stable.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      try fakeRecRepo.expectCalls(methodName: "candidateEpisodes", count: 1)
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("rec-sort with empty scoring result reaches .ready so empty-state UI is reachable")
  func loadingStateReachesReadyAfterEmptyRecScoring() async throws {
    let fakeRecRepo =
      Container.shared.recommendationRepo() as! FakeRecommendationRepo
    fakeRecRepo.candidateEpisodesScript([
      { [] }
    ])

    let viewModel = EpisodesListViewModel(title: "EmptyRecReady")
    viewModel.currentSortMethod = .recommendationScore

    let observationTask = Task { @MainActor in
      await runObservationLoop(viewModel)
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .ready },
        { @MainActor in
          """
          Expected .ready after empty rec-scoring landed so noEpisodesMessage \
          can render; got \(viewModel.loadingState).
          """
        }
      )
      #expect(viewModel.episodeList.filteredEntries.isEmpty)
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("loadingState defaults to .loadingEpisodes and reaches .ready for non-rec sort")
  func loadingStateForNonRecSort() async throws {
    let setup = try await setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "NonRecLoadingState")
    #expect(viewModel.loadingState == .loadingEpisodes)

    let observationTask = Task { @MainActor in
      await viewModel.startObservation()
    }

    do {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .ready },
        { @MainActor in
          "Expected .ready, got \(viewModel.loadingState)."
        }
      )
    } catch {
      observationTask.cancel()
      viewModel.disappear()
      throw error
    }

    #expect(viewModel.episodeList.filteredEntries.count == setup.episodes.count)
    observationTask.cancel()
    viewModel.disappear()
  }

  @Test("uncacheSelectedEpisodes leaves cache files alone when bulk unsave throws")
  func uncacheSelectedEpisodesPreservesCacheOnUnsaveFailure() async throws {
    let cachedEpisode = try await CacheHelpers.createCachedEpisode(
      title: "ep1",
      cachedFilename: "ep1.mp3",
      saveInCache: true
    )
    let cachedURL = try #require(cachedEpisode.cachedURL)
    #expect(fileManager.fileExists(at: cachedURL.rawValue))

    let listables = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.NoOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }
    let viewModel = EpisodesListViewModel(title: "Test")
    try await loadEntries(into: viewModel, episodes: listables)
    select(viewModel, ids: [cachedEpisode.id])

    let fakeRepo = self.fakeRepo
    fakeRepo.updateSaveInCacheBulkError(InjectedRepoError())
    fakeRepo.clearAllCalls()

    viewModel.uncacheSelectedEpisodes()

    try await Wait.until(
      { (try? fakeRepo.expectCalls(methodName: "updateSaveInCache")) != nil },
      { "uncacheSelectedEpisodes never invoked updateSaveInCache" }
    )

    // The buggy path keeps going after the throw and runs clearCache, which
    // records updateCachedFilename on its way to clearing the file. Poll for
    // that side effect; a timeout means the early-return fix held.
    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(20),
        priority: .userInitiated,
        { (try? fakeRepo.expectCalls(methodName: "updateCachedFilename")) != nil },
        { "regression: clearCache ran despite updateSaveInCache throwing" }
      )
      Issue.record("regression: clearCache ran despite updateSaveInCache throwing")
    } catch {
      // Expected timeout under the fixed implementation.
    }

    try fakeRepo.expectNoCall(methodName: "updateCachedFilename")
    #expect(fileManager.fileExists(at: cachedURL.rawValue))

    let final = try #require(try await repo.episode(cachedEpisode.id))
    #expect(final.cachedURL == cachedEpisode.cachedURL)
    #expect(final.cacheStatus == .cached)
    #expect(final.saveInCache)
  }

  // MARK: - Helpers

  private struct Setup {
    let ep1: Episode
    let ep2: Episode
    let ep3: Episode
    let ep4: Episode
    let tagA: PodHaven.Tag
    let tagB: PodHaven.Tag
    let tagC: PodHaven.Tag
    let episodes: [ListablePodcastEpisode]
  }

  private func setupFourTaggedEpisodes() async throws -> Setup {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "ep1"),
          try Create.unsavedEpisode(guid: "ep2"),
          try Create.unsavedEpisode(guid: "ep3"),
          try Create.unsavedEpisode(guid: "ep4"),
        ]
      )
    )
    let ep1 = series.episodes[0]
    let ep2 = series.episodes[1]
    let ep3 = series.episodes[2]
    let ep4 = series.episodes[3]

    let tagA = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let tagB = try await repo.insertTag(UnsavedTag(name: "Beta"))
    let tagC = try await repo.insertTag(UnsavedTag(name: "Cherry"))

    try await repo.addTag(tagA.id, to: ep1.id)
    try await repo.addTag(tagB.id, to: ep1.id)
    try await repo.addTag(tagB.id, to: ep2.id)
    try await repo.addTag(tagC.id, to: ep2.id)
    try await repo.addTag(tagA.id, to: ep3.id)
    try await repo.addTag(tagB.id, to: ep3.id)
    try await repo.addTag(tagC.id, to: ep3.id)

    let episodes = try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: AppDB.NoOp, order: Episode.Columns.id.asc)
        .fetchAll(db)
    }

    return Setup(
      ep1: ep1,
      ep2: ep2,
      ep3: ep3,
      ep4: ep4,
      tagA: tagA,
      tagB: tagB,
      tagC: tagC,
      episodes: episodes
    )
  }

  private func loadEntries(
    into viewModel: EpisodesListViewModel,
    episodes: [ListablePodcastEpisode]
  ) async throws {
    viewModel.episodeList.allEntries = IdentifiedArray(uniqueElements: episodes)
    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == episodes.count },
      { @MainActor in
        "filteredEntries didn't populate; got \(viewModel.episodeList.filteredEntries.count)"
      }
    )
  }

  private func select(_ viewModel: EpisodesListViewModel, ids: [Episode.ID]) {
    for id in ids {
      viewModel.episodeList.isSelected[id] = true
    }
  }
}
