// Copyright Justin Bishop, 2024

import Foundation
import IdentifiedCollections

@Observable @MainActor final class UpNextViewModel {
  var podcastEpisodes: PodcastEpisodeArray = IdentifiedArrayOf<PodcastEpisode>()

  func moveItem(from source: IndexSet, to destination: Int) {
    guard source.count == 1 else { fatalError("Somehow dragged several?") }
    guard let from = source.first else { fatalError("No source in drag?") }
    print("moving from: \(from), to: \(destination)")
    Task {
      try await Repo.shared.insertToQueue(
        podcastEpisodes[from].episode.id,
        at: destination
      )
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
