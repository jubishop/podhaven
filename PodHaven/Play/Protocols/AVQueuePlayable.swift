// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

extension Container {
  var avQueuePlayer: Factory<any AVQueuePlayable> {
    Factory(self) { AVQueuePlayer() }.scope(.cached)
  }
}

@MainActor
protocol AVQueuePlayable {
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
}

extension AVQueuePlayer: AVQueuePlayable {
  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    guard let playerItem = item as? AVPlayerItem
    else { Assert.fatal("Inserting non AVPlayerItem into queue player?") }

    let afterPlayerItem = afterItem as? AVPlayerItem
    insert(playerItem, after: afterPlayerItem)
  }

  func items() -> [any AVPlayableItem] {
    (self as AVQueuePlayer).items() as [AVPlayerItem]
  }

  func remove(_ item: any AVPlayableItem) {
    guard let playerItem = item as? AVPlayerItem
    else { Assert.fatal("Removing non AVPlayerItem from queue player?") }

    remove(playerItem)
  }

  nonisolated public func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    observe(\.timeControlStatus, options: options) { player, _ in
      changeHandler(player.timeControlStatus)
    }
  }
}
