// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol PodcastEpisodeGettable {
  associatedtype EpisodeType

  func getPodcastEpisode(_ episode: EpisodeType) async throws -> PodcastEpisode
  func getEpisodeID(_ episode: EpisodeType) async throws -> Episode.ID
}
