// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import IdentifiedCollections
import Observation
import Testing

@testable import PodHaven

@MainActor enum EpisodesListTestHelpers {
  private static var repo: any Databasing { Container.shared.repo() }

  // Mirrors Episode.candidate (unstarted && unfinished && !rated && unqueued)
  // in SmartListFilter form for SmartList-driven view models.
  static let candidateFilter = SmartListFilter(
    combinator: .all,
    conditions: [
      .state(.isUnstarted), .state(.isUnfinished), .state(.isUnrated), .state(.isUnqueued),
    ]
  )

  // Inserts a SmartList row and builds the view model from it, so the row
  // carries the desired sort up front instead of racing a write-through toggle.
  static func makeViewModel(
    title: String,
    filter: SmartListFilter = SmartListFilter(),
    sortMethod: SmartListSortMethod = .newestFirst
  ) async throws -> EpisodesListViewModel {
    let smartListRepo = Container.shared.smartListRepo()
    let maxDisplayOrder = try await smartListRepo.fetchAll().map(\.displayOrder).max()
    let smartList = try await smartListRepo.insert(
      try UnsavedSmartList(
        title: title,
        filter: filter,
        displayOrder: (maxDisplayOrder ?? -1) + 1,
        sortMethod: sortMethod
      )
    )
    return EpisodesListViewModel(smartList: smartList)
  }

  struct Setup {
    let ep1: Episode
    let ep2: Episode
    let ep3: Episode
    let ep4: Episode
    let tagA: PodHaven.Tag
    let tagB: PodHaven.Tag
    let tagC: PodHaven.Tag
    let episodes: [ListablePodcastEpisode]
  }

  static func setupFourTaggedEpisodes() async throws -> Setup {
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
        .request(filter: AppDB.noOp, order: Episode.Columns.id.asc)
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

  static func loadEntries(
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

  static func select(_ viewModel: EpisodesListViewModel, ids: [Episode.ID]) {
    for id in ids {
      viewModel.episodeList.isSelected[id] = true
    }
  }
}

@MainActor
final class LoadingStateRecorder {
  private(set) var values: [EpisodesListViewModel.LoadingState] = []
  private let viewModel: EpisodesListViewModel

  init(viewModel: EpisodesListViewModel) {
    self.viewModel = viewModel
    capture()
  }

  private func capture() {
    let value = viewModel.loadingState
    if values.last != value { values.append(value) }
    withObservationTracking {
      _ = viewModel.loadingState
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.capture()
      }
    }
  }
}
