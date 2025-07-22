// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayerItem: AVPlayableItem {
  var episodeID: Episode.ID? {
    guard let urlAsset = asset as? AVURLAsset
    else { Assert.fatal("\(asset) is not an AVURLAsset") }

    return urlAsset.episodeID
  }

  nonisolated func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayerItem.Status) -> Void
  ) -> NSKeyValueObservation {
    observe(\.status, options: options) { playerItem, _ in
      changeHandler(playerItem.status)
    }
  }
}
