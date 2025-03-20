// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol UnsavedPodcastQueueableModel: EpisodeQueueable
where EpisodeType == UnsavedEpisode {
  var unsavedPodcast: UnsavedPodcast { get }
}

@MainActor extension UnsavedPodcastQueueableModel {
  func playEpisode(_ episode: UnsavedEpisode) {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await Container.shared.playManager().load(podcastEpisode)
      await Container.shared.playManager().play()
    }
  }

  func queueEpisodeOnTop(_ episode: UnsavedEpisode) {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await Container.shared.queue().unshift(podcastEpisode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: UnsavedEpisode) {
    Task {
      let repo = Container.shared.repo()
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await Container.shared.queue().append(podcastEpisode.id)
    }
  }
}
