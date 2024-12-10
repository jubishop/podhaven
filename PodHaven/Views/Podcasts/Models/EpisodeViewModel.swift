// Copyright Justin Bishop, 2024

import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  var episode: Episode

  init(episode: Episode) {
    self.episode = episode
  }

  // TODO: Observe a PodcastEpisode instead
  func observeEpisode() async {
    do {
      let observer =
        ValueObservation
        .tracking(Episode.filter(id: episode.id).fetchOne)
        .removeDuplicates()

      for try await episode in observer.values(
        in: PodcastRepository.shared.db
      ) {
        guard self.episode != episode else { return }
        guard let episode = episode else {
          Alert.shared(
            "No return from DB for episode: \(self.episode.toString)"
          )
          return
        }
        self.episode = episode
      }
    } catch {
      Alert.shared(
        "Error thrown while observing episode: \(self.episode.toString)"
      )
    }
  }

}
