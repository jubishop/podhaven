// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import IdentifiedCollections

@Observable @MainActor final class SeriesViewModel {
  var podcastSeries: PodcastSeries
  var podcast: Podcast { podcastSeries.podcast }
  var episodes: IdentifiedArray<String, Episode> { podcastSeries.episodes }

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast)
  }

  func refreshSeries() async throws {
    let feedTask = await FeedManager.shared.addURL(podcast.feedURL)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let feedData):
      guard let newPodcast = feedData.feed.toPodcast(mergingExisting: podcast)
      else {
        throw FeedError.failedParse(
          "Failed to refresh series: \(podcast.toString)"
        )
      }
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in feedData.feed.items {
        if let existingEpisode = episodes[id: feedItem.guid] {
          if let newExistingEpisode = try? feedItem.toEpisode(
            mergingExisting: existingEpisode
          ) {
            existingEpisodes.append(newExistingEpisode)
          }
        } else if let newUnsavedEpisode = try? feedItem.toUnsavedEpisode() {
          unsavedEpisodes.append(newUnsavedEpisode)
        }
      }
      try await Repo.shared.updateSeries(
        newPodcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    }
  }

  func observePodcast() async {
    do {
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

      for try await podcastSeries in observer.values(in: Repo.shared.db) {
        guard let podcastSeries = podcastSeries else {
          Alert.shared("No return from DB for: \(podcast.toString)")
          return
        }
        self.podcastSeries = podcastSeries
      }
    } catch {
      Alert.shared("Error thrown while observing: \(podcast.toString)")
    }
  }
}
