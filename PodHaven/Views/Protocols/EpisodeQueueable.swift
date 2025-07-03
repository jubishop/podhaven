// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol EpisodeQueueable {
  associatedtype EpisodeType

  func playEpisode(_ episode: EpisodeType)
  func queueEpisodeOnTop(_ episode: EpisodeType)
  func queueEpisodeAtBottom(_ episode: EpisodeType)
}
