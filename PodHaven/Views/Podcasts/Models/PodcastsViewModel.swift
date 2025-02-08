// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  let gridID = "grid"

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func refreshPodcasts() async throws {
    let allSeries = try await repo.allPodcastSeries {
      $0.filter(Schema.subscribedColumn == true && Schema.lastUpdateColumn < Date.minutesAgo(1))
    }
    try await withThrowingDiscardingTaskGroup { group in
      for podcastSeries in allSeries {
        group.addTask {
          try await self.refreshManager.refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }

  func observePodcasts() async throws {
    let observer =
      ValueObservation
      .tracking { db in
        try Podcast
          .filter(Schema.subscribedColumn == true)
          .fetchIdentifiedArray(db, id: \Podcast.feedURL)
      }
      .removeDuplicates()
    for try await podcasts in observer.values(in: repo.db) {
      self.podcasts = podcasts
    }
  }
}
