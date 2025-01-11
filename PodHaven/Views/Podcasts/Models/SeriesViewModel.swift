// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class SeriesViewModel {
  @ObservationIgnored @Injected(\.repo) private var repo

  var podcastSeries: PodcastSeries
  var podcast: Podcast { podcastSeries.podcast }
  var episodes: IdentifiedArray<String, Episode> { podcastSeries.episodes }

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast)
  }

  func refreshSeries() async throws {
    try await FeedManager.refreshSeries(podcastSeries: podcastSeries)
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
