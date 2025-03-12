// Copyright Justin Bishop, 2025 

import Foundation

@MainActor protocol EpisodePlayable {
  associatedtype EpisodeType
  func playEpisode(_ episode: EpisodeType)
}
