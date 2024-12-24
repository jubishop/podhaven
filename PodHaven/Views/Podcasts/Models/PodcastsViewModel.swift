// Copyright Justin Bishop, 2024

import Foundation
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func observePodcasts() async {
    do {
      for try await podcasts in Observatory.allPodcasts.values() {
        self.podcasts = podcasts
      }
    } catch {
      Alert.shared("Error thrown while observing all podcasts in database")
    }
  }
}
