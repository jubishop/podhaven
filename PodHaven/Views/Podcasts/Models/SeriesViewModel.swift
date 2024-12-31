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
    try await FeedManager.refreshSeries(podcastSeries: podcastSeries)
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
