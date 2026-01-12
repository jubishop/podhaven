// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

extension AVPlayerItem: AVPlayableItem {
  nonisolated func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayerItem.Status) -> Void
  ) -> NSKeyValueObservation {
    observe(\.status, options: options) { playerItem, _ in
      changeHandler(playerItem.status)
    }
  }
}
