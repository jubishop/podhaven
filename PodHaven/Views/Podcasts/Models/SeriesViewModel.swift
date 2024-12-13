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
      else { return }
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
      try await PodcastRepository.shared.insertSeries(
        newPodcast,
        unsavedEpisodes: unsavedEpisodes,
        existingEpisodes: existingEpisodes
      )
    }
  }

  func observePodcasts() async {
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

      for try await podcastSeries in observer.values(
        in: PodcastRepository.shared.db
      ) {
        guard self.podcastSeries != podcastSeries else { return }
        guard let podcastSeries = podcastSeries else {
          Alert.shared("No return from DB for podcast: \(podcast.toString)")
          return
        }
        self.podcastSeries = podcastSeries
      }
    } catch {
      Alert.shared("Error thrown while observing podcast: \(podcast.toString)")
    }
  }
}
