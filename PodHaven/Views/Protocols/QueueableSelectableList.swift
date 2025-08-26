// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol QueueableSelectableList {
  func addSelectedEpisodesToTopOfQueue()
  func addSelectedEpisodesToBottomOfQueue()
  func replaceQueueWithSelected()
  func replaceQueueWithSelectedAndPlay()
  func cacheSelectedEpisodes()
}
