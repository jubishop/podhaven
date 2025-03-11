// Copyright Justin Bishop, 2025

import Foundation

@MainActor protocol QueueableSelectableList {
  func addSelectedEpisodesToTopOfQueue()
  func addSelectedEpisodesToBottomOfQueue()
  func replaceQueue()
  func replaceQueueAndPlay()
}
