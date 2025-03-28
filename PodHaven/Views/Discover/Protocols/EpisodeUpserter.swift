// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol EpisodeUpserter {
  associatedtype EpisodeType

  func upsert(_ episode: EpisodeType) async throws -> PodcastEpisode
}
