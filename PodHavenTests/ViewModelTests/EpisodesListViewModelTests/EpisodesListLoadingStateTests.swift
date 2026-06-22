// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel loading state tests", .container)
@MainActor final class EpisodesListLoadingStateTests {
  @Test("loadingState is .neverLoaded during rec-sort cold start until scoring lands")
  func loadingStateIsNeverLoadedOnRecSortColdStart() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(
      title: "RecLoadingState",
      sortMethod: .recommendationScore
    )

    let recorder = LoadingStateRecorder(viewModel: viewModel)

    try await withRunningObservationLoop(viewModel) {
      // The cold-start path starts in `.neverLoaded`, which renders the same
      // loading UI until the candidate observation emits and scoring lands.
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
        recorder.values.contains(.neverLoaded),
        """
        Expected rec-sort cold start to pass through .neverLoaded before reaching .loaded. \
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

  @Test("filter-text change after empty result stays loaded without re-entering .loading")
  func emptyFilterTextChangeDoesNotFlashLoadingState() async throws {
    let repo = Container.shared.repo()
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "EmptyFilterTextPodcast"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "Gammaempty Episode"),
          try Create.unsavedEpisode(title: "Deltaempty Episode"),
        ]
      )
    )

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(
      title: "EmptyFilterTextLoadingState"
    )
    let fakeObservatory = try #require(Container.shared.observatory() as? FakeObservatory)

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

      let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
      var pendingSleepCount = fakeSleeper.pendingCount()
      viewModel.filterDebouncer.currentValue = "Missingempty"
      try await fakeSleeper.waitForSleepRequests(count: pendingSleepCount + 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && viewModel.displayObservationKey.filterText == "Missingempty"
            && viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          """
          Expected first filter to settle as a loaded empty result; got \
          \(viewModel.loadingState), key \(viewModel.displayObservationKey), entries \
          \(viewModel.episodeList.filteredEntries.map(\.title)).
          """
        }
      )

      let recorder = LoadingStateRecorder(viewModel: viewModel)
      let initialListableObservationCount =
        fakeObservatory.allCallsInOrder
        .filter { $0.methodName == "listablePodcastEpisodes(filter:order:limit:)" }
        .count

      fakeObservatory.holdNextListablePodcastEpisodesDelivery()
      defer { fakeObservatory.releaseHeldListablePodcastEpisodesDelivery() }
      pendingSleepCount = fakeSleeper.pendingCount()
      viewModel.filterDebouncer.currentValue = "Stillmissingempty"
      try await fakeSleeper.waitForSleepRequests(count: pendingSleepCount + 1)
      await fakeSleeper.advanceTime(by: .milliseconds(500))

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          fakeObservatory.allCallsInOrder
            .filter { $0.methodName == "listablePodcastEpisodes(filter:order:limit:)" }
            .count > initialListableObservationCount
        },
        { @MainActor in
          """
          Expected the empty-result filter edit to start a new listable episode observation; \
          calls: \(fakeObservatory.allCallsInOrder.map(\.toString)).
          """
        }
      )

      #expect(
        viewModel.loadingState == .loaded,
        """
        Editing a loaded empty standard-sort result must keep the view in the loaded \
        empty state while the new observation is waiting to emit. Got \(viewModel.loadingState).
        """
      )

      fakeObservatory.releaseHeldListablePodcastEpisodesDelivery()

      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && viewModel.displayObservationKey.filterText == "Stillmissingempty"
            && viewModel.episodeList.filteredEntries.isEmpty
        },
        { @MainActor in
          """
          Expected second empty filter to remain loaded; got \(viewModel.loadingState), \
          key \(viewModel.displayObservationKey), entries \
          \(viewModel.episodeList.filteredEntries.map(\.title)).
          """
        }
      )

      #expect(
        !recorder.values.contains(.loading),
        """
        Editing a loaded empty standard-sort result must not flash .loading. \
        Recorded transitions: \(recorder.values)
        """
      )
    }
  }

  @Test("loadingState defaults to .neverLoaded and reaches .loaded for non-rec sort")
  func loadingStateForNonRecSort() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "NonRecLoadingState")
    if case .neverLoaded = viewModel.loadingState {
    } else {
      Issue.record("Expected initial state .neverLoaded, got \(viewModel.loadingState)")
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
