// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor protocol AVQueuePlayable {
  var current: (any AVPlayableItem)? { get }
  var queued: [any AVPlayableItem] { get }
  func insert(_: any AVPlayableItem, after: (any AVPlayableItem)?)
  func remove(_: any AVPlayableItem)
  func removeAllItems()
  func observeCurrentItem(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping ((any AVPlayableItem)?) -> Void
  ) -> NSKeyValueObservation

  func play()
  func pause()
  func seek(to: CMTime, completionHandler: @Sendable @escaping (Bool) -> Void)

  func currentTime() -> CMTime
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @Sendable @escaping (CMTime) -> Void
  ) -> Any
  func removeTimeObserver(_ observer: Any)

  var timeControlStatus: AVPlayer.TimeControlStatus { get }
  var reasonForWaitingToPlay: AVPlayer.WaitingReason? { get }
  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation
}
