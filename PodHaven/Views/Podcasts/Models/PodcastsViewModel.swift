// Copyright Justin Bishop, 2024

import Combine
import Foundation
import GRDB

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: [Podcast] = []

  private let repository: PodcastRepository

  init(repository: PodcastRepository = .shared) {
    self.repository = repository
  }

  func observePodcasts() async {
    do {
      for try await podcasts in repository.observer.values() {
        self.podcasts = podcasts
      }
    } catch {
      Alert.shared("Error thrown while observing podcast database")
    }
  }
}
