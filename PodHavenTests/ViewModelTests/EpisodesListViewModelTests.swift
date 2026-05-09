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
      uniqueElements: [setup.ep4.id, setup.ep3.id, setup.ep2.id, setup.ep1.id].compactMap { id in
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
