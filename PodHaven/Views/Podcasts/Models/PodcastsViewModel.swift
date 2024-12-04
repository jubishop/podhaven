// Copyright Justin Bishop, 2024

import Foundation

@Observable @MainActor final class PodcastsViewModel {
  private let repository: PodcastRepository

  init(repository: PodcastRepository = .shared) {
    self.repository = repository
  }
}
