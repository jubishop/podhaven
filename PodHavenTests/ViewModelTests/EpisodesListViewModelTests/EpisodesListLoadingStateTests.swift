// Copyright Justin Bishop, 2026

import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel loading state tests", .container)
@MainActor final class EpisodesListLoadingStateTests {
  @Test("loadingState is .computingRecommendations during rec-sort cold start")
  func loadingStateIsComputingRecommendationsOnRecSortColdStart() async throws {
    let viewModel = EpisodesListViewModel(title: "RecLoadingState")
    viewModel.currentSortMethod = .recommendationScore

    let recorder = LoadingStateRecorder(viewModel: viewModel)

    try await withRunningObservationLoop(viewModel) {
      // The cold-start path is: startDisplayObservation runs sync and sets
      // `.computingRecommendations` (rec sort + .pending scores) before the
      // candidate observation has emitted. Once the candidate observation
      // emits its empty list and scoring lands, state moves to `.loaded`.
      // The recorder catches the intermediate state because the production
      // gap between those two transitions spans at least one GRDB
      // observation hop.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          """
          Expected .loaded with empty filteredEntries after empty scoring landed; got \
          state \(viewModel.loadingState) with \
          \(viewModel.episodeList.filteredEntries.count) entries.
          """
        }
      )

      #expect(
        recorder.values.contains(.computingRecommendations),
        """
        Expected rec-sort cold start to pass through .computingRecommendations \
        before reaching .loaded. Recorded loadingState transitions: \(recorder.values)
        """
      )
    }
  }

  @Test("rec-sort with empty scoring result reaches .loaded([]) so empty-state UI is reachable")
  func loadingStateReachesLoadedAfterEmptyRecScoring() async throws {
    let viewModel = EpisodesListViewModel(title: "EmptyRecReady")
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          """
          Expected .loaded with empty filteredEntries after empty rec-scoring landed so \
          emptyEpisodesMessage can render; got state \(viewModel.loadingState) with \
          \(viewModel.episodeList.filteredEntries.count) entries.
          """
        }
      )
    }
  }

  @Test("loadingState defaults to .loadingEpisodes and reaches .loaded for non-rec sort")
  func loadingStateForNonRecSort() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "NonRecLoadingState")
    if case .loadingEpisodes = viewModel.loadingState {
    } else {
      Issue.record("Expected initial state .loadingEpisodes, got \(viewModel.loadingState)")
    }

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && viewModel.episodeList.filteredEntries.count == setup.episodes.count
        },
        { @MainActor in
          """
          Expected .loaded with \(setup.episodes.count) filteredEntries, got state \
          \(viewModel.loadingState) with \(viewModel.episodeList.filteredEntries.count) entries.
          """
        }
      )
    }
  }
}
