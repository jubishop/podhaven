// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor
class PersonEpisodeViewModel:
  QueueableUnsavedEpisodeConverter,
  UnsavedEpisodeQueueableModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory

  internal let unsavedPodcastEpisode: UnsavedPodcastEpisode
  internal var podcastEpisode: PodcastEpisode?

  init(unsavedPodcastEpisode: UnsavedPodcastEpisode) {
    self.unsavedPodcastEpisode = unsavedPodcastEpisode
  }

  func execute() async {
    do {
      for try await podcastEpisode in observatory.podcastEpisode(unsavedEpisode.media) {
        if self.podcastEpisode == podcastEpisode { continue }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      alert.andReport(error)
    }
  }
}
