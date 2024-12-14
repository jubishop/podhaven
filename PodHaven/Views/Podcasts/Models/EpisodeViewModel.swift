// Copyright Justin Bishop, 2024

import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  var podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  func observeEpisode() async {
    do {
      let observer =
        ValueObservation
        .tracking(
          Episode
            .filter(id: episode.id)
            .including(required: Episode.podcast)
            .asRequest(of: PodcastEpisode.self)
            .fetchOne
        )
        .removeDuplicates()

      for try await podcastEpisode in observer.values(in: Repo.shared.db) {
        guard self.podcastEpisode != podcastEpisode else { return }
        guard let podcastEpisode = podcastEpisode else {
          Alert.shared(
            "No return from DB for episode: \(episode.toString)"
          )
          return
        }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      Alert.shared(
        "Error thrown while observing episode: \(self.episode.toString)"
      )
    }
  }

}
