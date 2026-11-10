// Copyright Justin Bishop, 2026

import FactoryKit
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel selection tests", .container)
@MainActor final class EpisodesListSelectionTests {
  @DynamicInjected(\.repo) private var repo

  @Test("selectedEpisodesTagIntersection collapses to common tags across selection")
  func selectedEpisodesTagIntersectionAcrossSelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
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

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
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

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep4.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection and union are empty when no episodes are selected")
  func selectedEpisodesTagHelpersOnEmptySelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    #expect(viewModel.selectedEpisodesTagIntersection == [])
    #expect(viewModel.selectedEpisodesTagUnion == [])
  }

  @Test("selectedEpisodesTagIntersection equals selected episode's tags for a single selection")
  func selectedEpisodesTagIntersectionForSingleSelection() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)

    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep2.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [setup.tagB.id, setup.tagC.id])
    #expect(viewModel.selectedEpisodesTagUnion == [setup.tagB.id, setup.tagC.id])
  }

  @Test("resolving the selection preserves user-visible selection order")
  func resolvedSelectionPreservesSelectionOrder() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    // Visible order is reversed from DB rowid order so the test fails if
    // `WHERE id IN (...)` row order leaks through `resolvedPodcastEpisodes`.
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

    let podcastEpisodes = try await viewModel.resolvedPodcastEpisodes(for: viewModel.selectedEpisodes)
      .map(\.podcastEpisode)
    #expect(
      podcastEpisodes.map(\.id) == [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id]
    )
  }

  // Regression: bulk actions snapshotted the selection for their checks but
  // resolved episode IDs from the live selection inside their Task, so a
  // selection change in between acted on episodes the user hadn't chosen.
  @Test("a bulk action acts on the selection at the time it was requested")
  func bulkActionUsesSelectionAtRequestTime() async throws {
    let setup = try await EpisodesListTestHelpers.setupFourTaggedEpisodes()

    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Test")
    try await EpisodesListTestHelpers.loadEntries(into: viewModel, episodes: setup.episodes)
    EpisodesListTestHelpers.select(viewModel, ids: [setup.ep1.id, setup.ep2.id])

    viewModel.addSelectedEpisodesToBottomOfQueue()
    viewModel.episodeList.isSelected[setup.ep2.id] = false
    viewModel.episodeList.isSelected[setup.ep3.id] = true

    let repo = repo
    let ep1ID = setup.ep1.id
    let ep2ID = setup.ep2.id
    try await Wait.until(
      {
        let ep1 = try await repo.episode(ep1ID)
        let ep2 = try await repo.episode(ep2ID)
        return ep1?.queued == true && ep2?.queued == true
      },
      { "Expected the episodes selected at request time to be queued" }
    )
    withExtendedLifetime(viewModel) {}

    let ep3 = try #require(try await repo.episode(setup.ep3.id))
    #expect(!ep3.queued)
  }
}
