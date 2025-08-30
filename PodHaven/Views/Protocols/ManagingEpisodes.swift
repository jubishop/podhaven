// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol ManagingEpisodes {
  func playEpisode(_ episode: any EpisodeDisplayable)
  func queueEpisodeOnTop(_ episode: any EpisodeDisplayable)
  func queueEpisodeAtBottom(_ episode: any EpisodeDisplayable)
  func cacheEpisode(_ episode: any EpisodeDisplayable)
}
