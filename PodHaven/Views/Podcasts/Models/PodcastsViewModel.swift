// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func refreshPodcasts() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for podcast in podcasts {
        group.addTask {
          try await FeedManager.refreshSeries(podcast: podcast)
        }
      }
    }
  }

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
