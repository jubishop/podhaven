// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol ManagingEpisodes {
  associatedtype EpisodeType

  func playEpisode(_ episode: EpisodeType)
  func queueEpisodeOnTop(_ episode: EpisodeType)
  func queueEpisodeAtBottom(_ episode: EpisodeType)
  func cacheEpisode(_ episode: EpisodeType)
}
