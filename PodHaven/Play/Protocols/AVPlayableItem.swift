// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVPlayableItem: AnyObject, CustomStringConvertible {
  var asset: AVAsset { get }
  var status: AVPlayerItem.Status { get }

  func observeStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayerItem.Status, (any Error)?) -> Void
  ) -> NSKeyValueObservation
}
