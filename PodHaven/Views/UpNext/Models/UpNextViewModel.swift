// Copyright Justin Bishop, 2024

import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class UpNextViewModel {
  var podcastEpisodes: PodcastEpisodeArray = IdentifiedArray(
    id: \PodcastEpisode.episode.media
  )
  var editMode: EditMode = .inactive
  var isEditing: Bool { editMode == .active }
  var isSelected = BindableDictionary<PodcastEpisode, Bool>(defaultValue: false)
  var anySelected: Bool { isSelected.values.contains(true) }

  func moveItem(from: IndexSet, to: Int) {
    precondition(from.count == 1, "Somehow dragged several?")
    guard let from = from.first else { fatalError("No from in drag?") }
    Task {
      try await Repo.shared.insertToQueue(
        podcastEpisodes[from].episode.id,
        at: to
      )
    }
  }

  func moveToTop(_ podcastEpisode: PodcastEpisode) {
    Task { try await Repo.shared.unshiftToQueue(podcastEpisode.episode.id) }
  }

  func deleteSelected() {
    Task {
      for selectedItem in isSelected.keys.filter({ isSelected[$0] }) {
        try await Repo.shared.dequeue(selectedItem.episode.id)
      }
    }
  }

  func deleteItem(_ podcastEpisode: PodcastEpisode) {
    Task {
      try await Repo.shared.dequeue(podcastEpisode.episode.id)
    }
  }

  func deleteAll() {
    Task {
      try await Repo.shared.clearQueue()
      editMode = .inactive
    }
  }

  func unselectAll() {
    isSelected.removeAll()
  }

  func observeQueuedEpisodes() async {
    do {
      for try await podcastEpisodes in Observatory.queuedEpisodes.values() {
        self.podcastEpisodes = podcastEpisodes
        for podcastEpisode in isSelected.keys {
          if !podcastEpisodes.contains(podcastEpisode) {
            isSelected.removeValue(forKey: podcastEpisode)
          }
        }
      }
    } catch {
      Alert.shared("Error thrown while observing queued episodes in db")
    }
  }
}
