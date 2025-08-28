// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol SelectableEpisodeList {
  func addSelectedEpisodesToTopOfQueue()
  func addSelectedEpisodesToBottomOfQueue()
  func replaceQueueWithSelected()
  func replaceQueueWithSelectedAndPlay()
  func cacheSelectedEpisodes()
}
