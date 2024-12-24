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
      Alert.shared(error.errorDescription)
    case .success(let feedData):
      guard let newPodcast = feedData.feed.toPodcast(mergingExisting: podcast)
      else { fatalError("Failed to refresh series: \(podcast.toString)") }
      var unsavedEpisodes: [UnsavedEpisode] = []
      var existingEpisodes: [Episode] = []
      for feedItem in feedData.feed.items {
        if let existingEpisode = episodes[id: feedItem.guid] {
          existingEpisodes.append(
            feedItem.toEpisode(mergingExisting: existingEpisode)
          )
        } else {
          unsavedEpisodes.append(feedItem.toUnsavedEpisode())
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
