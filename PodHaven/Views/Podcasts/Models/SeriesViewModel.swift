// Copyright Justin Bishop, 2024

import Foundation
import GRDB

@Observable @MainActor final class SeriesViewModel {
  var podcastSeries: PodcastSeries
  var podcast: Podcast { podcastSeries.podcast }
  var episodes: Set<Episode> { podcastSeries.episodes }

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast, episodes: [])
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
