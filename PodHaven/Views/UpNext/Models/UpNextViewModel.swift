// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue

  var podcastEpisodes: PodcastEpisodeArray = IdentifiedArray(id: \PodcastEpisode.episode.media)
  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }
  var isSelected = BindableDictionary<PodcastEpisode, Bool>(defaultValue: false)
  var anySelected: Bool { isSelected.values.contains(true) }

  func moveItem(from: IndexSet, to: Int) {
    precondition(from.count == 1, "Somehow dragged several?")
    guard let from = from.first else { fatalError("No from in drag?") }

    Task { try await queue.insert(podcastEpisodes[from].episode.id, at: to) }
  }

  func moveToTop(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.unshift(podcastEpisode.episode.id) }
  }

  func deleteSelected() {
    Task {
      for selectedItem in isSelected.keys.filter({ isSelected[$0] }) {
        try await queue.dequeue(selectedItem.episode.id)
      }
    }
  }

  func deleteItem(_ podcastEpisode: PodcastEpisode) {
    Task { try await queue.dequeue(podcastEpisode.episode.id) }
  }

  func deleteAll() {
    Task {
      try await queue.clear()
      editMode = .inactive
    }
  }

  func unselectAll() {
    isSelected.removeAll()
  }

  func observeQueuedEpisodes() async throws {
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
      for podcastEpisode in isSelected.keys {
        if !podcastEpisodes.contains(podcastEpisode) {
          isSelected.removeValue(forKey: podcastEpisode)
        }
      }
    }
  }
}
