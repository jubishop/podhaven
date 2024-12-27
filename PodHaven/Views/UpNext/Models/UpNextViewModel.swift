// Copyright Justin Bishop, 2024

import Foundation
import IdentifiedCollections

@Observable @MainActor final class UpNextViewModel {
  var podcastEpisodes: PodcastEpisodeArray = IdentifiedArray(
    id: \PodcastEpisode.episode.media
  )
  var isSelected = BindableDictionary<PodcastEpisode, Bool>(defaultValue: false)

  func moveItem(from: IndexSet, to: Int) {
    guard from.count == 1 else { fatalError("Somehow dragged several?") }
    guard let from = from.first else { fatalError("No from in drag?") }
    Task {
      try await Repo.shared.insertToQueue(
        podcastEpisodes[from].episode.id,
        at: to
      )
    }
  }

  func moveToTop(_ podcastEpisode: PodcastEpisode) {
    Task {
      try await Repo.shared.unshiftToQueue(podcastEpisode.episode.id)
    }
  }

  func deleteOffsets(at offsets: IndexSet) {
    Task {
      for offset in offsets.reversed() {
        try await Repo.shared.dequeue(podcastEpisodes[offset].episode.id)
      }
    }
  }

  func deleteSelected() {
    Task {
      for selectedItem in isSelected.keys.filter({ isSelected[$0] }) {
        try await Repo.shared.dequeue(selectedItem.episode.id)
      }
    }
  }

  func observeQueuedEpisodes() async {
    do {
      for try await podcastEpisodes in Observatory.queuedEpisodes.values() {
        self.podcastEpisodes = podcastEpisodes
      }
    } catch {
      Alert.shared("Error thrown while observing queued episodes in db")
    }
  }
}
