// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of podcast delete confirmation tests", .container)
@MainActor final class PodcastDeleteConfirmationTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.repo) private var repo

  @Test("deleting one podcast from a list asks first, keeps it on Cancel, and deletes on Delete")
  func listSingleDeleteConfirms() async throws {
    let kept = try await insertPodcast(titled: "Kept Podcast")
    let deleted = try await insertPodcast(titled: "Deleted Podcast")
    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()
    let viewModel = PodcastsListViewModel(title: "Test")

    viewModel.deletePodcast(try #require(entries.first { $0.id == kept }).podcast)
    let cancelled = try await answerAlert("Cancel")

    #expect(cancelled.title == "Delete Podcast?")
    #expect(cancelled.message == "Are you sure you want to delete \"Kept Podcast\"?")
    #expect(try await repo.podcastSeries(kept) != nil)

    viewModel.deletePodcast(try #require(entries.first { $0.id == deleted }).podcast)
    let confirmed = try await answerAlert("Delete")

    #expect(confirmed.message == "Are you sure you want to delete \"Deleted Podcast\"?")
    try await waitUntilDeleted([deleted])
    #expect(try await repo.podcastSeries(kept) != nil)
  }

  @Test("deleting selected podcasts asks first, keeps them on Cancel, and deletes on Delete")
  func listBulkDeleteConfirms() async throws {
    let first = try await insertPodcast(titled: "First")
    let second = try await insertPodcast(titled: "Second")
    let unselected = try await insertPodcast(titled: "Unselected")
    let entries = try await observatory.listablePodcastsWithEpisodeMetadata().get()
    let viewModel = PodcastsListViewModel(title: "Test")
    viewModel.podcastList.allEntries = IdentifiedArray(uniqueElements: entries)
    try await Wait.until(
      { @MainActor in viewModel.podcastList.filteredEntries.count == entries.count },
      { @MainActor in
        "Expected \(entries.count) entries; got \(viewModel.podcastList.filteredEntries.count)"
      }
    )
    viewModel.podcastList.isSelected[first] = true
    viewModel.podcastList.isSelected[second] = true

    viewModel.deleteSelectedPodcasts()
    let cancelled = try await answerAlert("Cancel")

    #expect(cancelled.title == "Delete Podcasts?")
    #expect(cancelled.message == "Are you sure you want to delete 2 podcasts?")
    for podcastID in [first, second, unselected] {
      #expect(try await repo.podcastSeries(podcastID) != nil)
    }

    viewModel.deleteSelectedPodcasts()
    try await answerAlert("Delete")

    try await waitUntilDeleted([first, second])
    #expect(try await repo.podcastSeries(unselected) != nil)
  }

  @Test("deleting from podcast detail asks first, keeps it on Cancel, and deletes on Delete")
  func detailDeleteConfirms() async throws {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Detail Podcast"),
        unsavedEpisodes: [try Create.unsavedEpisode()]
      )
    )
    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(series.podcast))
    try await PodcastDetailTestHelpers.appear(viewModel)

    viewModel.delete()
    let cancelled = try await answerAlert("Cancel")

    #expect(cancelled.title == "Delete Podcast?")
    #expect(cancelled.message == "Are you sure you want to delete \"Detail Podcast\"?")
    #expect(try await repo.podcastSeries(series.id) != nil)

    viewModel.delete()
    try await answerAlert("Delete")

    try await waitUntilDeleted([series.id])
  }

  // MARK: - Helpers

  private func insertPodcast(titled title: String) async throws -> Podcast.ID {
    try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(title: title))
    )
    .id
  }

  private func waitUntilDeleted(_ podcastIDs: [Podcast.ID]) async throws {
    try await Wait.until(
      { @MainActor in
        for podcastID in podcastIDs where try await self.repo.podcastSeries(podcastID) != nil {
          return false
        }
        return true
      },
      { @MainActor in "Expected podcasts \(podcastIDs) to be deleted" }
    )
  }
}
