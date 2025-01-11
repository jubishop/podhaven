// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  @ObservationIgnored @Injected(\.repo) private var repo

  private var podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  var onDeck: Bool { PlayState.shared.isOnDeck(podcastEpisode) }

  func playNow() {
    Task { @PlayActor in
      try await PlayManager.shared.load(podcastEpisode)
      PlayManager.shared.play()
    }
  }

  func addToTopOfQueue() {
    Task {
      try await repo.unshiftToQueue(episode.id)
    }
  }

  func appendToQueue() {
    Task {
      try await repo.appendToQueue(episode.id)
    }
  }

  func observeEpisode() async throws {
    let observer =
      ValueObservation.tracking(
        Episode
          .filter(id: episode.id)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne
      )
      .removeDuplicates()

    for try await podcastEpisode in observer.values(in: repo.db) {
      guard let podcastEpisode = podcastEpisode
      else { throw Err.msg("No return from DB for: \(episode.toString)") }
      self.podcastEpisode = podcastEpisode
    }
  }
}
