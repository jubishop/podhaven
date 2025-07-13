// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

class FakeAVPlayerItem: AVPlayableItem {
  let episodeID: Episode.ID?

  init(episodeID: Episode.ID?) {
    self.episodeID = episodeID
  }

  nonisolated var description: String {
    String(describing: episodeID)
  }

  func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @escaping @Sendable (AVPlayerItem.Status) -> Void
  ) -> NSKeyValueObservation {
    return NSObject().observe(\.description, options: []) { _, _ in }
  }
}
