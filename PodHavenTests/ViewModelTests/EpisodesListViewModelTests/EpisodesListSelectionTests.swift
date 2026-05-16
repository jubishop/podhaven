// Copyright Justin Bishop, 2026

import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel selection tests", .container)
@MainActor final class EpisodesListSelectionTests {
  @Test("selectedEpisodesTagIntersection collapses to common tags across selection")
  func selectedEpisodesTagIntersectionAcrossSelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    // ep1 = {A, B}, ep2 = {B, C}, ep3 = {A, B, C} → common is {B}.
    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep1.id, setup.ep2.id, setup.ep3.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [setup.tagB.id])
    #expect(
      viewModel.selectedEpisodesTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test("selectedEpisodesTagIntersection collapses to empty when an untagged episode is selected")
  func selectedEpisodesTagIntersectionWithUntagged() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    // Adding ep4 (no tags) drags the intersection to empty even though
    // ep1, ep3 share {A, B}; the union still reports every tag in play.
    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep1.id, setup.ep3.id, setup.ep4.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(
      viewModel.selectedEpisodesTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test(
    "selectedEpisodesTagIntersection and union are empty when only untagged episodes are selected"
  )
  func selectedEpisodesTagHelpersOnUntaggedOnly() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep4.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection and union are empty when no episodes are selected")
  func selectedEpisodesTagHelpersOnEmptySelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection equals selected episode's tags for a single selection")
  func selectedEpisodesTagIntersectionForSingleSelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = EpisodesListViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep2.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [setup.tagB.id, setup.tagC.id])
    #expect(viewModel.selectedEpisodesTagUnion == [setup.tagB.id, setup.tagC.id])
  }

  @Test("selectedPodcastEpisodes preserves user-visible selection order")
  func selectedPodcastEpisodesPreservesSelectionOrder() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

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

    EpisodesListTestHelpers.select(
      viewModel,
      ids: [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id]
    )

    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(
      podcastEpisodes.map(\.id) == [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id]
    )
  }
}
