// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel loading state tests", .container)
@MainActor final class EpisodesListLoadingStateTests {
  @Test("loadingState is .loading during rec-sort cold start until scoring lands")
  func loadingStateIsLoadingOnRecSortColdStart() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(
      title: "RecLoadingState",
      sortMethod: .recommendationScore
    )

    let recorder = LoadingStateRecorder(viewModel: viewModel)

    try await withRunningObservationLoop(viewModel) {
      // The cold-start path: startDisplayObservation runs sync and sets
      // `.loading` before the candidate observation has emitted. Once the
      // candidate observation emits its empty list and scoring lands, state
      // moves to `.loaded`. The recorder catches the intermediate `.loading`
      // because the production gap between those two transitions spans at
      // least one GRDB observation hop.
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
        recorder.values.contains(.loading),
        """
        Expected rec-sort cold start to pass through .loading before reaching .loaded. \
        Recorded loadingState transitions: \(recorder.values)
        """
      )
    }
  }

  @Test("rec-sort with empty scoring result reaches .loaded([]) so empty-state UI is reachable")
  func loadingStateReachesLoadedAfterEmptyRecScoring() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(
      title: "EmptyRecReady",
      sortMethod: .recommendationScore
    )

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

  @Test("filter-text change updates a loaded list in place without re-entering .loading")
  func filterTextChangeDoesNotFlashLoadingState() async throws {
    let repo = Container.shared.repo()
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "FilterTextPodcast"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "Alphaunique Episode"),
          try Create.unsavedEpisode(title: "Betaunique Episode"),
        ]
      )
    )

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "FilterTextLoadingState")

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded && viewModel.episodeList.filteredEntries.count == 2
        },
        { @MainActor in
          """
          Expected .loaded with 2 entries before filtering; got \(viewModel.loadingState) \
          with \(viewModel.episodeList.filteredEntries.count) entries.
          """
        }
      )

      // Record loadingState transitions from the settled .loaded baseline.
      let recorder = LoadingStateRecorder(viewModel: viewModel)

      // Typing in the filter field drives filterText through the debouncer,
      // which restarts the display observation exactly as production's
      // `.task(id:)` does.
      viewModel.filterDebouncer.currentValue = "Alphaunique"
      let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
      try await fakeSleeper.waitForSleepRequests(count: 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.episodeList.filteredEntries.map(\.title) == ["Alphaunique Episode"]
        },
        { @MainActor in
          """
          Expected the filter text to narrow results to the Alphaunique episode; got \
          \(viewModel.episodeList.filteredEntries.map(\.title)).
          """
        }
      )

      #expect(
        !recorder.values.contains(.loading),
        """
        Refining the filter text must update results in place; flashing .loading tears \
        down the list and drops the search field's keyboard focus. \
        Recorded transitions: \(recorder.values)
        """
      )
    }
  }

  @Test("loadingState defaults to .loading and reaches .loaded for non-rec sort")
  func loadingStateForNonRecSort() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "NonRecLoadingState")
    if case .loading = viewModel.loadingState {
    } else {
      Issue.record("Expected initial state .loading, got \(viewModel.loadingState)")
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
