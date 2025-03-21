// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol UnsavedPodcastSubscribableModel: AnyObject, Observable {
  var subscribable: Bool { get set }
  var unsavedPodcast: UnsavedPodcast { get set }
  var episodeList: SelectableListUseCase<UnsavedEpisode, GUID> { get set }
  var existingPodcastSeries: PodcastSeries? { get }
  var podcastFeed: PodcastFeed? { get }

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
}
