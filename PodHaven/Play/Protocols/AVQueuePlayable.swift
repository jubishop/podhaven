// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVQueuePlayable {
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @Sendable @escaping (CMTime) -> Void
  ) -> Any
  func currentTime() -> CMTime
  func insert(_: any AVPlayableItem, after: (any AVPlayableItem)?)
  func items() -> [any AVPlayableItem]
  func pause()
  func play()
  func remove(_: any AVPlayableItem)
  func removeAllItems()
  func removeTimeObserver(_ observer: Any)
  func seek(to: CMTime, completionHandler: @Sendable @escaping (Bool) -> Void)
  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation
  var reasonForWaitingToPlay: AVPlayer.WaitingReason? { get }
}
