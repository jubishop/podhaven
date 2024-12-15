// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func observePodcasts() async {
    do {
      for try await podcasts in Repo.shared.observer.values() {
        self.podcasts = podcasts
      }
    } catch {
      Alert.shared("Error thrown while observing podcast database")
    }
  }
}
