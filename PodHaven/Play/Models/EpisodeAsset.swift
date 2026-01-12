// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor struct EpisodeAsset {
  private let playerItemFactory: @MainActor () -> any AVPlayableItem
  let isPlayable: Bool
  let duration: CMTime

  init(
    isPlayable: Bool,
    duration: CMTime,
    playerItemFactory: @escaping @MainActor () -> any AVPlayableItem
  ) {
    self.isPlayable = isPlayable
    self.duration = duration
    self.playerItemFactory = playerItemFactory
  }

  func playerItem() -> any AVPlayableItem {
    playerItemFactory()
  }
}
