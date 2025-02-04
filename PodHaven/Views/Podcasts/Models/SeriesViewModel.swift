// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class SeriesViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  var podcastSeries: PodcastSeries
  var podcast: Podcast { podcastSeries.podcast }
  var episodes: EpisodeArray { podcastSeries.episodes }

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast)
  }

  func refreshIfStale() async throws {
    if podcastSeries.podcast.lastUpdate < Date.minutesAgo(15),
      let podcastSeries = try await repo.podcastSeries(podcastSeries.id)
    {
      self.podcastSeries = podcastSeries
      try await refreshSeries()
    }
  }

  func refreshSeries() async throws {
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func subscribe() async throws {
    try await repo.markSubscribed(podcast.id)
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

      if self.podcastSeries == podcastSeries { continue }
      self.podcastSeries = podcastSeries
    }
  }
}
