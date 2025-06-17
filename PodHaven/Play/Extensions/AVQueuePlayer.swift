// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

extension Container {
  var avQueuePlayer: Factory<any AVQueuePlayable> {
    Factory(self) { AVQueuePlayer() }.scope(.cached)
  }
}

extension AVQueuePlayer: AVQueuePlayable {
  var current: (any AVPlayableItem)? { currentItem }
  var queued: [any AVPlayableItem] { items() }
  nonisolated func observeCurrentItem(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (MediaURL?) -> Void
  ) -> NSKeyValueObservation {
    observe(\.currentItem, options: options) { player, _ in
      Task { @MainActor in
        changeHandler(player.currentItem?.assetURL)
      }
    }
  }

  func insert(_ item: any AVPlayableItem, after afterItem: (any AVPlayableItem)?) {
    guard let playerItem = item as? AVPlayerItem
    else { Assert.fatal("Inserting non AVPlayerItem into queue player?") }

    let afterPlayerItem = afterItem as? AVPlayerItem
    insert(playerItem, after: afterPlayerItem)
  }

  func remove(_ item: any AVPlayableItem) {
    guard let playerItem = item as? AVPlayerItem
    else { Assert.fatal("Removing non AVPlayerItem from queue player?") }

    remove(playerItem)
  }

  nonisolated func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    observe(\.timeControlStatus, options: options) { player, _ in
      changeHandler(player.timeControlStatus)
    }
  }
}
