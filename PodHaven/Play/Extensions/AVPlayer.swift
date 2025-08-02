// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

extension Container {
  var avPlayer: Factory<any AVPlayable> {
    Factory(self) { AVPlayer() }.scope(.cached)
  }
}

extension AVPlayer: AVPlayable {
  var current: (any AVPlayableItem)? { currentItem }
  func replaceCurrent(with item: (any AVPlayableItem)?) {
    guard let item
    else {
      replaceCurrentItem(with: nil)
      return
    }

    if let playerItem = item as? AVPlayerItem {
      replaceCurrentItem(with: playerItem)
    } else {
      Assert.fatal("Replacing current item with non PlayerItem? : \(item)")
    }
  }

  nonisolated func observeTimeControlStatus(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (AVPlayer.TimeControlStatus) -> Void
  ) -> NSKeyValueObservation {
    observe(\.timeControlStatus, options: options) { player, _ in
      changeHandler(player.timeControlStatus)
    }
  }

  nonisolated func observeRate(
    options: NSKeyValueObservingOptions,
    changeHandler: @Sendable @escaping (Float) -> Void
  ) -> NSKeyValueObservation {
    observe(\.rate, options: options) { player, _ in
      changeHandler(player.rate)
    }
  }
}
