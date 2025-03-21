// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor class TitleEpisodeViewModel: UnsavedEpisodeQueueableModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observer) private var observer

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
