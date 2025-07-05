// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

class FakeAVPlayerItem: AVPlayableItem {
  let episodeID: Episode.ID?

  init(episodeID: Episode.ID?) {
    self.episodeID = episodeID
  }

  nonisolated var description: String {
    "TODO"
    //    String(describing: episodeID)
  }
}
