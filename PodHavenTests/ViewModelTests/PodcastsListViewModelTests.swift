// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PodcastsListViewModel tests", .container)
@MainActor final class PodcastsListViewModelTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("selectedPodcastsTagIntersection collapses to common tags across selection")
  func selectedPodcastsTagIntersectionAcrossSelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    // pod1 = {A, B}, pod2 = {B, C}, pod3 = {A, B, C} → common is {B}.
    select(viewModel, ids: [setup.pod1, setup.pod2, setup.pod3])
    #expect(viewModel.selectedPodcastsTagIntersection == [setup.tagB.id])
    #expect(
      viewModel.selectedPodcastsTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection collapses to empty when an untagged podcast is selected")
  func selectedPodcastsTagIntersectionWithUntagged() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    // Adding pod4 (no tags) drags the intersection to empty even though
    // pod1, pod3 share {A, B}; the union still reports every tag in play.
    select(viewModel, ids: [setup.pod1, setup.pod3, setup.pod4])
    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(
      viewModel.selectedPodcastsTagUnion == [setup.tagA.id, setup.tagB.id, setup.tagC.id]
    )
  }

  @Test(
    "selectedPodcastsTagIntersection and union are empty when only untagged podcasts are selected"
  )
  func selectedPodcastsTagHelpersOnUntaggedOnly() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    select(viewModel, ids: [setup.pod4])
    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(viewModel.selectedPodcastsTagUnion == [])
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection and union are empty when no podcasts are selected")
  func selectedPodcastsTagHelpersOnEmptySelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    #expect(viewModel.selectedPodcastsTagIntersection == [])
    #expect(viewModel.selectedPodcastsTagUnion == [])
    #expect(!viewModel.selectionHasTagData)
  }

  @Test("selectedPodcastsTagIntersection equals selected podcast's tags for a single selection")
  func selectedPodcastsTagIntersectionForSingleSelection() async throws {
    let setup = try await setupFourTaggedPodcasts()

    let viewModel = PodcastsListViewModel(title: "Test")
    try await loadEntries(into: viewModel, podcasts: setup.entries)

    select(viewModel, ids: [setup.pod2])
    #expect(viewModel.selectedPodcastsTagIntersection == [setup.tagB.id, setup.tagC.id])
    #expect(viewModel.selectedPodcastsTagUnion == [setup.tagB.id, setup.tagC.id])
  }

  // MARK: - Helpers

  private struct Setup {
    let pod1: Podcast.ID
    let pod2: Podcast.ID
    let pod3: Podcast.ID
    let pod4: Podcast.ID
    let tagA: PodHaven.Tag
    let tagB: PodHaven.Tag
    let tagC: PodHaven.Tag
    let entries: [PodcastWithEpisodeMetadata<ListablePodcast>]
  }

  private func setupFourTaggedPodcasts() async throws -> Setup {
    let p1 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p1.rss")!),
            title: "P1"
          )
        )
      )
      .id
    let p2 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p2.rss")!),
            title: "P2"
          )
        )
      )
      .id
    let p3 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p3.rss")!),
            title: "P3"
          )
        )
      )
      .id
    let p4 =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(URL(string: "https://example.com/p4.rss")!),
            title: "P4"
          )
        )
      )
      .id

    let tagA = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let tagB = try await repo.insertTag(UnsavedTag(name: "Beta"))
    let tagC = try await repo.insertTag(UnsavedTag(name: "Cherry"))

    try await repo.addTag(tagA.id, to: p1)
    try await repo.addTag(tagB.id, to: p1)
    try await repo.addTag(tagB.id, to: p2)
    try await repo.addTag(tagC.id, to: p2)
    try await repo.addTag(tagA.id, to: p3)
    try await repo.addTag(tagB.id, to: p3)
    try await repo.addTag(tagC.id, to: p3)

    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()

    return Setup(
      pod1: p1,
      pod2: p2,
      pod3: p3,
      pod4: p4,
      tagA: tagA,
      tagB: tagB,
      tagC: tagC,
      entries: entries
    )
  }

  private func loadEntries(
    into viewModel: PodcastsListViewModel,
    podcasts: [PodcastWithEpisodeMetadata<ListablePodcast>]
  ) async throws {
    viewModel.podcastList.allEntries = IdentifiedArray(uniqueElements: podcasts)
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntries.count == podcasts.count },
      { @MainActor in
        "filteredEntries didn't populate; got \(viewModel.podcastList.filteredEntries.count)"
      }
    )
  }

  private func select(_ viewModel: PodcastsListViewModel, ids: [Podcast.ID]) {
    for id in ids {
      viewModel.podcastList.isSelected[id] = true
    }
  }
}
