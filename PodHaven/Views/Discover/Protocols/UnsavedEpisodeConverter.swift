// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol UnsavedEpisodeConverter: QueueableEpisodeConverter
where EpisodeType == UnsavedEpisode {
  var unsavedPodcast: UnsavedPodcast { get }
}

@MainActor extension UnsavedEpisodeConverter {
  func upsertToPodcastEpisode(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    let repo = Container.shared.repo()
    return try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: episode
      )
    )
  }
}
