// Copyright Justin Bishop, 2024

import Combine
import Foundation
import GRDB

@Observable @MainActor final class PodcastsViewModel {
  var podcasts: [Podcast] = []

  private let repository: PodcastRepository
  @ObservationIgnored private var cancellable: AnyCancellable?

  init(repository: PodcastRepository = .shared) {
    self.repository = repository
  }

  func observePodcasts() {
    self.cancellable = self.repository.observer.publisher()
      .sink(
        receiveCompletion: { completion in
          Alert.shared("Stopped observing podcasts in the database")
        },
        receiveValue: { [unowned self] (podcasts: [Podcast]) in
          self.podcasts = podcasts
        }
      )
  }
}
