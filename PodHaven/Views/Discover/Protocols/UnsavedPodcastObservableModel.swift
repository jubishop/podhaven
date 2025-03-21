// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections

@MainActor protocol UnsavedPodcastObservableModel: AnyObject, Observable {
  var existingPodcastSeries: PodcastSeries? { get set }
  var podcastFeed: PodcastFeed? { get }
  var subscribable: Bool { get set }
  var unsavedEpisodes: [UnsavedEpisode] { get }
  var unsavedPodcast: UnsavedPodcast { get set }

  func processPodcastSeries(_ podcastSeries: PodcastSeries?) throws
  func subscribe()
}

@MainActor extension UnsavedPodcastObservableModel {
  func processPodcastSeries(_ podcastSeries: PodcastSeries?) throws {
    if let podcastSeries = podcastSeries, podcastSeries.podcast.subscribed {
      Container.shared.navigation().showPodcast(podcastSeries)
    }

    guard let podcastFeed = self.podcastFeed
    else { throw Err.msg("Can't call processPodcastSeries without a podcastFeed") }

    existingPodcastSeries = podcastSeries
    if let podcastSeries = existingPodcastSeries {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
    } else {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false, lastUpdate: Date.epoch)
    }

    subscribable = true
  }

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
              unsavedEpisodes: unsavedEpisodes
            )
          Container.shared.navigation().showPodcast(newPodcastSeries)
        }
      } catch {
        Container.shared.alert().andReport(error)
      }
    }
  }
}
