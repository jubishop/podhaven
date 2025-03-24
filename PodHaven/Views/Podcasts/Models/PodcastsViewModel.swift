// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class PodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  func execute() async {
    do {
      for try await podcasts in observatory.allPodcasts(Schema.subscribedColumn == true) {
        self.podcasts = podcasts
      }
    } catch {
      alert.andReport(error)
    }
  }

  func refreshPodcasts() async throws {
    let allSeries = try await repo.allPodcastSeries(
      Schema.subscribedColumn == true && Schema.lastUpdateColumn < Date.minutesAgo(1)
    )
    try await withThrowingDiscardingTaskGroup { group in
      for podcastSeries in allSeries {
        group.addTask {
          try await self.refreshManager.refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }
}
