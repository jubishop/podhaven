// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVPlayableItem: CustomStringConvertible {
  var asset: AVAsset { get }

  func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayerItem.Status) -> Void
  ) -> NSKeyValueObservation
}
