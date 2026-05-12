// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastDetailViewModel selection tests", .container)
@MainActor final class SelectionTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.repo) private var repo

  @Test("selected episode tag helpers use saved episode tag IDs")
  func selectedEpisodeTagHelpersUseSavedEpisodeTagIDs() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Tagged Detail"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "detail-tagged-1"),
          try Create.unsavedEpisode(guid: "detail-tagged-2"),
        ]
      )
    )
    let firstEpisode = savedSeries.episodes[0]
    let secondEpisode = savedSeries.episodes[1]
    let alpha = try await repo.insertTag(UnsavedTag(name: "Alpha"))
    let beta = try await repo.insertTag(UnsavedTag(name: "Beta"))
    let cherry = try await repo.insertTag(UnsavedTag(name: "Cherry"))

    try await repo.addTag(alpha.id, to: firstEpisode.id)
    try await repo.addTag(beta.id, to: firstEpisode.id)
    try await repo.addTag(beta.id, to: secondEpisode.id)
    try await repo.addTag(cherry.id, to: secondEpisode.id)

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in viewModel.episodeList.allEntries.count == 2 },
      { @MainActor in
        "Expected saved podcast detail episodes to load before selection."
      }
    )

    try PodcastDetailTestHelpers.select(viewModel, episodeIDs: [firstEpisode.id, secondEpisode.id])
    #expect(viewModel.selectedEpisodesTagIntersection == [beta.id])
    #expect(viewModel.selectedEpisodesTagUnion == [alpha.id, beta.id, cherry.id])
    #expect(viewModel.selectionHasTagData)
  }

  @Test("selectionHasTagData is false when any selected episode is unsaved")
  func selectionHasTagDataFalseForUnsavedSelection() async throws {
    let unsavedSeries = UnsavedPodcastSeries(
      unsavedPodcast: try Create.unsavedPodcast(title: "Unsaved Tag Gate"),
      unsavedEpisodes: [
        try Create.unsavedEpisode(guid: "unsaved-tag-gate-1"),
        try Create.unsavedEpisode(guid: "unsaved-tag-gate-2"),
      ]
    )
    let viewModel = PodcastDetailViewModel(unsavedPodcastSeries: unsavedSeries)
    _ = try await repo.insertTag(UnsavedTag(name: "Alpha"))

    try await Wait.until(
      { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
      { @MainActor in
        "Expected unsaved series episodes to seed before selection."
      }
    )

    for entry in viewModel.episodeList.allEntries {
      viewModel.episodeList.isSelected[entry.id] = true
    }

    // Bulk tag actions on unsaved selections would silently upsert just to
    // attach a tag — the gate keeps the menu hidden so the per-row
    // "no tag UI for unsaved rows" contract holds across both surfaces.
    #expect(viewModel.selectionHasTagData == false)
  }

  @Test("selectedPodcastEpisodes preserves user-visible selection order")
  func selectedPodcastEpisodesPreservesSelectionOrder() async throws {
    // Insertion order = ep1, ep2, ep3 (so DB rowid order matches that).
    // pubDates are reversed so `oldestFirst` flips the visible order to
    // [ep3, ep2, ep1] — different from any "natural" SQL ordering, which
    // is what reveals the bug if `WHERE id IN (...)` returns rows in
    // rowid order rather than the input ID order.
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Selection Order"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: "sel-order-1",
            title: "Newest",
            pubDate: Date(timeIntervalSince1970: 300)
          ),
          try Create.unsavedEpisode(
            guid: "sel-order-2",
            title: "Middle",
            pubDate: Date(timeIntervalSince1970: 200)
          ),
          try Create.unsavedEpisode(
            guid: "sel-order-3",
            title: "Oldest",
            pubDate: Date(timeIntervalSince1970: 100)
          ),
        ]
      )
    )
    let newest = savedSeries.episodes[0]
    let middle = savedSeries.episodes[1]
    let oldest = savedSeries.episodes[2]

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()
    viewModel.currentSortMethod = .oldestFirst

    try await Wait.until(
      { @MainActor in
        viewModel.episodeList.filteredEntries.map(\.title) == ["Oldest", "Middle", "Newest"]
      },
      { @MainActor in
        """
        Expected oldestFirst sort to flip the visible order before selecting.
        Actual titles: \(viewModel.episodeList.filteredEntries.map(\.title))
        """
      }
    )

    try PodcastDetailTestHelpers.select(viewModel, episodeIDs: [oldest.id, middle.id, newest.id])

    // selectedEpisodes follows filteredEntries (visible) order, so the
    // returned PodcastEpisodes must match — anything else means the
    // `WHERE id IN (...)` row-order leaked into bulk Play / Replace Queue.
    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(podcastEpisodes.map(\.id) == [oldest.id, middle.id, newest.id])
  }

  @Test("selectedPodcastEpisodes degrades to [] when DB rows vanish under a live selection")
  func selectedPodcastEpisodesGracefulOnVanishedRows() async throws {
    let savedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "About to be deleted"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "vanish-1", title: "First"),
          try Create.unsavedEpisode(guid: "vanish-2", title: "Second"),
        ]
      )
    )

    let viewModel = PodcastDetailViewModel(podcast: DisplayedPodcast(savedSeries.podcast))
    try await viewModel.performAppear()

    try await Wait.until(
      { @MainActor in
        viewModel.saved && viewModel.episodeList.allEntries.count == 2
      },
      { @MainActor in
        """
        Expected episodeList to hydrate before selection.
        saved: \(viewModel.saved)
        count: \(viewModel.episodeList.allEntries.count)
        """
      }
    )

    try PodcastDetailTestHelpers.select(viewModel, episodeIDs: savedSeries.episodes.map(\.id))
    #expect(viewModel.selectedEpisodes.count == 2)

    // disappear() first so the deletion's `nil` emission can't race the
    // assertion via `loadPresentationFromFeed`.
    viewModel.disappear()

    let deleted = try await repo.deletePodcast(savedSeries.id)
    #expect(deleted)

    let podcastEpisodes = try await viewModel.selectedPodcastEpisodes
    #expect(podcastEpisodes.isEmpty)

    try await Wait.until(
      { @MainActor [self] in alert.config != nil },
      { @MainActor [self] in
        """
        Expected an alert when selectedPodcastEpisodes degrades to [].
        alert presented: \(alert.config != nil)
        """
      }
    )
  }
}
