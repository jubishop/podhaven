// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class SeriesViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.feedManager) private var feedManager

  var podcastSeries: PodcastSeries
  var podcast: Podcast { podcastSeries.podcast }
  var episodes: EpisodeArray { podcastSeries.episodes }

  convenience init(podcast: Podcast) {
    self.init(podcastSeries: PodcastSeries(podcast: podcast))
  }

  init(podcastSeries: PodcastSeries) {
    self.podcastSeries = podcastSeries
  }

  func refreshSeries() async throws {
    try await feedManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func observePodcast() async throws {
    let observer =
      ValueObservation
      .tracking(
        Podcast
          .filter(id: podcast.id)
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchOne
      )
      .removeDuplicates()

    for try await podcastSeries in observer.values(in: repo.db) {
      guard let podcastSeries = podcastSeries
      else { throw Err.msg("No return from DB for: \(podcast.toString)") }
      self.podcastSeries = podcastSeries
    }
  }
}
