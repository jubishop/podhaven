// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@MainActor protocol UnsavedPodcastSubscribableModel: UnsavedPodcastObservableModel {
  var subscribable: Bool { get set }

  func subscribe()
}

@MainActor extension UnsavedPodcastSubscribableModel {
  func subscribe() {
    guard subscribable
    else { return }

    Task {
      do {
        if let podcastSeries = existingPodcastSeries, let podcastFeed = self.podcastFeed {
          var podcast = podcastSeries.podcast
          podcast.subscribed = true
          let updatedPodcastSeries = PodcastSeries(
            podcast: podcast,
            episodes: podcastSeries.episodes
          )
          try await Container.shared.refreshManager()
            .updateSeriesFromFeed(
              podcastSeries: updatedPodcastSeries,
              podcastFeed: podcastFeed
            )
          Container.shared.navigation().showPodcast(updatedPodcastSeries)
        } else {
          unsavedPodcast.subscribed = true
          unsavedPodcast.lastUpdate = Date()
          let newPodcastSeries = try await Container.shared.repo()
            .insertSeries(
              unsavedPodcast,
              unsavedEpisodes: Array(episodeList.allEntries)
            )
          Container.shared.navigation().showPodcast(newPodcastSeries)
        }
      } catch {
        Container.shared.alert().andReport(error)
      }
    }
  }

  func processPodcastSeries(_ podcastSeries: PodcastSeries?) throws {
    try (self as UnsavedPodcastObservableModel).processPodcastSeries(podcastSeries)
    subscribable = true
  }
}
