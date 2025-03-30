// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class StandardPodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  let title: String
  let podcastFilter: SQLSpecificExpressible
  var podcasts: PodcastArray = IdentifiedArray(id: \Podcast.feedURL)

  init(title: String, podcastFilter: SQLSpecificExpressible = true.sqlExpression) {
    self.title = title
    self.podcastFilter = podcastFilter
  }

  func execute() async {
    do {
      for try await podcasts in observatory.allPodcasts(podcastFilter) {
        self.podcasts = podcasts
      }
    } catch {
      alert.andReport(error)
    }
  }

  func refreshPodcasts() async throws {
    try await withThrowingDiscardingTaskGroup { group in
      let stalePodcastSeries: PodcastSeriesArray = try await repo.allPodcastSeries(
        Schema.lastUpdateColumn < 1.minutesAgo && podcastFilter
      )
      for podcastSeries in stalePodcastSeries {
        group.addTask {
          try await Container.shared.refreshManager().refreshSeries(podcastSeries: podcastSeries)
        }
      }
    }
  }
}
