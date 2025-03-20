// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor class TrendingEpisodeViewModel: UnsavedEpisodeQueueableModel {
  @ObservationIgnored private let alert = Container.shared.alert()
  @ObservationIgnored private let observer = Container.shared.observer()

  internal let unsavedPodcastEpisode: UnsavedPodcastEpisode
  internal var podcastEpisode: PodcastEpisode?

  init(unsavedPodcastEpisode: UnsavedPodcastEpisode) {
    self.unsavedPodcastEpisode = unsavedPodcastEpisode
  }

  func execute() async {
    do {
      for try await podcastEpisode in observer.observePodcastEpisode(unsavedEpisode.media) {
        if self.podcastEpisode == podcastEpisode { continue }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      alert.andReport(error)
    }
  }
}
