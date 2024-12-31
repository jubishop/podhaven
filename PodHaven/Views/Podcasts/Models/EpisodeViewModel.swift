// Copyright Justin Bishop, 2024

import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  private var podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  var onDeck: Bool { PlayState.shared.isOnDeck(podcastEpisode) }

  func playNow() {
    Task { @PlayActor in
      await PlayManager.shared.load(podcastEpisode)
      PlayManager.shared.play()
    }
  }

  func addToTopOfQueue() {
    Task {
      try await Repo.shared.unshiftToQueue(episode.id)
    }
  }

  func appendToQueue() {
    Task {
      try await Repo.shared.appendToQueue(episode.id)
    }
  }

  func observeEpisode() async {
    do {
      let observer =
        ValueObservation.tracking(
          Episode
            .filter(id: episode.id)
            .including(required: Episode.podcast)
            .asRequest(of: PodcastEpisode.self)
            .fetchOne
        )
        .removeDuplicates()

      for try await podcastEpisode in observer.values(in: Repo.shared.db) {
        guard let podcastEpisode = podcastEpisode else {
          Alert.shared("No return from DB for: \(episode.toString)")
          return
        }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      Alert.shared("Error thrown while observing: \(episode.toString)")
    }
  }
}
