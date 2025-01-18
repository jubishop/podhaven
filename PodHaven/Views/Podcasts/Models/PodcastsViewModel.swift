// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  @ObservationIgnored @Injected(\.repo) private var repo
  @ObservationIgnored @Injected(\.feedManager) private var feedManager

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func refreshPodcasts() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      for podcast in podcasts {
        group.addTask {
          try await self.feedManager.refreshSeries(podcast: podcast)
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
