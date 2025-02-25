// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue

  // MARK: - State Management

  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }

  var episodeList: EpisodeListUseCase = EpisodeListUseCase()

  private var _podcastEpisodes: PodcastEpisodeArray = IdentifiedArray(
    id: \PodcastEpisode.episode.media
  )
  var podcastEpisodes: PodcastEpisodeArray {
    get { _podcastEpisodes }
    set {
      _podcastEpisodes = newValue
      episodeList.allEpisodes = EpisodeArray(
        uniqueElements: newValue.map((\.episode)),
        id: \Episode.guid
      )
    }
  }

  // MARK: - Initialization

  func execute() async {
    do {
      try await observeQueuedEpisodes()
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func moveItem(from: IndexSet, to: Int) {
    precondition(from.count == 1, "Somehow dragged several?")
    guard let from = from.first else { fatalError("No from in drag?") }

    Task { try await queue.insert(podcastEpisodes[from].episode.id, at: to) }
  }

  func moveToTop(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.unshift(podcastEpisode.episode.id) }
  }

  func deleteItem(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.dequeue(podcastEpisode.episode.id) }
  }

  func deleteSelected() {
    Task { try await queue.dequeue(episodeList.selectedEpisodeIDs) }
  }

  // MARK: - Private Helpers

  private func observeQueuedEpisodes() async throws {
    let observer =
      ValueObservation.tracking { db in
        try Episode
          .filter(Schema.queueOrderColumn != nil)
          .including(required: Episode.podcast)
          .order(Schema.queueOrderColumn.asc)
          .asRequest(of: PodcastEpisode.self)
          .fetchIdentifiedArray(db, id: \PodcastEpisode.episode.media)
      }
      .removeDuplicates()
    for try await podcastEpisodes in observer.values(in: repo.db) {
      self.podcastEpisodes = podcastEpisodes
    }
  }
}
