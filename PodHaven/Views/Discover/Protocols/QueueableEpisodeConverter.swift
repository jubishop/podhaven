// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol QueueableEpisodeConverter {
  associatedtype EpisodeType

  func upsertToPodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
}
