// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.feedManager) private var feedManager

  var podcastSeries: PodcastSeriesArray = IdentifiedArray(id: \PodcastSeries.podcast.feedURL)

  func refreshPodcasts() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for podcastSeries in self.podcastSeries {
        group.addTask {
          try await self.feedManager.refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }

  func observePodcasts() async throws {
    let observer =
      ValueObservation
      .tracking { db in
        try Podcast
          .all()
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchIdentifiedArray(db, id: \PodcastSeries.podcast.feedURL)
      }
      .removeDuplicates()
    for try await podcastSeries in observer.values(in: repo.db) {
      self.podcastSeries = podcastSeries
    }
  }
}
