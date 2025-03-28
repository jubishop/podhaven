// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol UnsavedEpisodeUpserter: EpisodeUpserter where EpisodeType == UnsavedEpisode {
  var unsavedPodcast: UnsavedPodcast { get }
}

@MainActor extension UnsavedEpisodeUpserter {
  func upsert(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    let repo = Container.shared.repo()
    return try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: episode
      )
    )
  }
}
