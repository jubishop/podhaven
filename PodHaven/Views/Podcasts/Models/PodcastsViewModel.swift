// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.feedManager) private var feedManager

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func refreshPodcasts() async throws {
    let allSeries = try await repo.allPodcastSeries()
    try await withThrowingDiscardingTaskGroup { group in
      for podcast in self.podcasts {
        if let podcastSeries = allSeries[id: podcast.feedURL] {
          group.addTask {
            try await self.feedManager.refreshSeries(podcastSeries: podcastSeries)
          }
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
          .fetchIdentifiedArray(db, id: \Podcast.feedURL)
      }
      .removeDuplicates()
    for try await podcasts in observer.values(in: repo.db) {
      self.podcasts = podcasts
    }
  }
}
