// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor struct EpisodeAsset {
  private let playerItemFactory: @MainActor () -> any AVPlayableItem
  var cacheContent: CachedAudioContent?
  let isPlayable: Bool
  let duration: CMTime?

  init(
    isPlayable: Bool,
    duration: CMTime,
    playerItemFactory: @escaping @MainActor () -> any AVPlayableItem
  ) {
    self.isPlayable = isPlayable
    let seconds = duration.seconds
    self.duration = duration.isNumeric && seconds.isFinite && seconds > 0 ? duration : nil
    self.playerItemFactory = playerItemFactory
  }

  func playerItem() -> any AVPlayableItem {
    playerItemFactory()
  }
}
