// Copyright Justin Bishop, 2024

import Combine
import Foundation
import GRDB

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: [Podcast] = []

  func observePodcasts() async {
    do {
      for try await podcasts in PodcastRepository.shared.observer.values() {
        guard self.podcasts != podcasts else { return }
        self.podcasts = podcasts
      }
    } catch {
      Alert.shared("Error thrown while observing podcast database")
    }
  }
}
