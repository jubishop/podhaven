// Copyright Justin Bishop, 2024

import Foundation
import IdentifiedCollections

@Observable @MainActor final class UpNextViewModel {
  var podcastEpisodes: PodcastEpisodeArray = IdentifiedArrayOf<PodcastEpisode>()

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
