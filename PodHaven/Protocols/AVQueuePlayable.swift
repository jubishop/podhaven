// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

protocol AVQueuePlayable: Sendable {
  func addPeriodicTimeObserver(
    forInterval interval: CMTime,
    queue: dispatch_queue_t?,
    using block: @Sendable @escaping (CMTime) -> Void
  ) -> Any
  func currentTime() -> CMTime
  func insert(_: AVPlayerItem, after: AVPlayerItem?)
  func items() -> [AVPlayerItem]
  func pause()
  func play()
  func remove(_: AVPlayerItem)
  func removeAllItems()
  func removeTimeObserver(_ observer: Any)
  func seek(to: CMTime, completionHandler: @Sendable @escaping (Bool) -> Void)
  func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation
}

extension AVQueuePlayer: @retroactive Sendable, AVQueuePlayable {
  nonisolated public func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    observe(\.timeControlStatus, options: options) { player, _ in
      changeHandler(player.timeControlStatus)
    }
  }
}
