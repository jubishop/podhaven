// Copyright Justin Bishop, 2026

import FactoryKit
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel smart list row tests", .container)
@MainActor final class EpisodesListSmartListRowTests {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.smartListRepo) private var smartListRepo

  // Inserts one loved and one unrated episode; returns their IDs.
  private func seedLovedAndUnratedEpisodes() async throws -> (
    loved: Episode.ID, unrated: Episode.ID
  ) {
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(guid: "loved"),
          try Create.unsavedEpisode(guid: "unrated"),
        ]
      )
    )
    let loved = series.episodes[0]
    try await repo.updateRating(loved.id, rating: .loved)
    return (loved: loved.id, unrated: series.episodes[1].id)
  }

  @Test("a filter edit on the row updates the view model and the displayed set live")
  func filterEditPropagatesToOpenList() async throws {
    let seeded = try await seedLovedAndUnratedEpisodes()
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Live Filter")

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.count == 2 },
        { @MainActor in
          "Expected both episodes before the filter edit; got \(viewModel.episodeList.filteredEntries.count)"
        }
      )

      let lovedOnly = SmartListFilter(combinator: .all, conditions: [.state(.isLoved)])
      try await smartListRepo.update(
        viewModel.smartListID,
        title: "Live Filter",
        filter: lovedOnly,
        alwaysShowPodcastImage: false
      )

      try await Wait.until(
        { @MainActor in viewModel.smartListFilter == lovedOnly },
        { @MainActor in
          "Expected the row observation to deliver the edited filter; got \(viewModel.smartListFilter)"
        }
      )
      try await Wait.until(
        { @MainActor in viewModel.episodeList.filteredEntries.map(\.id) == [seeded.loved] },
        { @MainActor in
          """
          Expected the displayed set to narrow to the loved episode; got \
          \(viewModel.episodeList.filteredEntries.map(\.id))
          """
        }
      )
    }
  }

  @Test("a sortMethod edit on the row updates currentSortMethod and reorders the displayed set")
  func sortMethodEditPropagatesToOpenList() async throws {
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "older", pubDate: 2.daysAgo),
          try Create.unsavedEpisode(title: "newer", pubDate: 1.daysAgo),
        ]
      )
    )
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Live Sort")

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries.map(\.title) == ["newer", "older"]
        },
        { @MainActor in
          """
          Expected newestFirst order before the sort edit; got \
          \(viewModel.episodeList.filteredEntries.map(\.title))
          """
        }
      )

      try await smartListRepo.updateSortMethod(viewModel.smartListID, to: .oldestFirst)

      try await Wait.until(
        { @MainActor in viewModel.currentSortMethod == .oldestFirst },
        { @MainActor in
          "Expected the row observation to deliver oldestFirst; got \(viewModel.currentSortMethod)"
        }
      )
      try await Wait.until(
        { @MainActor in
          viewModel.episodeList.filteredEntries.map(\.title) == ["older", "newer"]
        },
        { @MainActor in
          """
          Expected oldestFirst order after the sort edit; got \
          \(viewModel.episodeList.filteredEntries.map(\.title))
          """
        }
      )
    }
  }

  @Test("a title edit on the row renames the open list live")
  func titleEditPropagatesToOpenList() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Before")

    try await withRunningObservationLoop(viewModel) {
      try await smartListRepo.update(
        viewModel.smartListID,
        title: "After",
        filter: SmartListFilter(),
        alwaysShowPodcastImage: false
      )

      try await Wait.until(
        { @MainActor in viewModel.title == "After" },
        { @MainActor in
          "Expected the row observation to deliver the new title; got \(viewModel.title)"
        }
      )
    }
  }

  @Test("an alwaysShowPodcastImage edit on the row updates the open list live")
  func artworkEditPropagatesToOpenList() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Artwork")
    #expect(!viewModel.alwaysShowPodcastImage)

    try await withRunningObservationLoop(viewModel) {
      try await smartListRepo.update(
        viewModel.smartListID,
        title: "Artwork",
        filter: SmartListFilter(),
        alwaysShowPodcastImage: true
      )

      try await Wait.until(
        { @MainActor in viewModel.alwaysShowPodcastImage },
        { @MainActor in
          "Expected the row observation to deliver the artwork preference; got \(viewModel.alwaysShowPodcastImage)"
        }
      )
    }
  }

  @Test("setting currentSortMethod writes through to the row and converges")
  func sortPickWritesThroughToRow() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Write Through")

    try await withRunningObservationLoop(viewModel) {
      viewModel.currentSortMethod = .longest

      try await Wait.until(
        { @MainActor in viewModel.currentSortMethod == .longest },
        { @MainActor in
          "Expected the sort pick to round-trip through the row; got \(viewModel.currentSortMethod)"
        }
      )
      let row = try #require(try await smartListRepo.fetchOne(viewModel.smartListID))
      #expect(row.sortMethod == .longest)
    }
  }

  @Test("deleting the observed row pops the episodes tab to the hub")
  func rowDeletionPopsToHub() async throws {
    let viewModel = try await EpisodesListTestHelpers.makeViewModel(title: "Doomed")
    navigation.episodes.path = [.smartList(viewModel.smartListID)]

    try await withRunningObservationLoop(viewModel) {
      try await smartListRepo.delete(viewModel.smartListID)

      try await Wait.until(
        { @MainActor in self.navigation.episodes.path.isEmpty },
        { @MainActor in
          "Expected the episodes path to pop to the hub; got \(self.navigation.episodes.path)"
        }
      )
    }
  }
}
