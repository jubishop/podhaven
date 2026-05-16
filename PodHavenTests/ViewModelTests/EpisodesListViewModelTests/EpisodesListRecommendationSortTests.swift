// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation sort tests", .container)
@MainActor final class EpisodesListRecommendationSortTests {
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

    try await withRunningObservationLoop(viewModel) {
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
    }
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

    try await withRunningObservationLoop(viewModel) {
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
    }
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

    try await withRunningObservationLoop(viewModel) {
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
    }
  }

  @Test("rec-sort hydrates only the top display rows after scoring")
  func recommendationSortHydratesOnlyTopDisplayRows() async throws {
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

    let fakeObservatory = try #require(Container.shared.observatory() as? FakeObservatory)
    fakeObservatory.clearAllCalls()

    let viewModel = EpisodesListViewModel(
      title: "RecTopHydration",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && !viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          """
          Expected rec sort to hydrate visible entries.
          State: \(viewModel.loadingState)
          Entries: \(viewModel.episodeList.filteredEntries.compactMap(\.episodeID))
          """
        }
      )

      let listableLimits =
        fakeObservatory
        .calls(of: MethodCall<Int>.self)
        .filter { $0.methodName == "listablePodcastEpisodes(filter:order:limit:)" }
        .map(\.parameters)
      #expect(listableLimits.contains(100))
      #expect(!listableLimits.contains(Int.max))
    }
  }

}
