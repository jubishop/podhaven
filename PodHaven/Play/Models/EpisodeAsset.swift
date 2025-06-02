// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor struct EpisodeAsset {
  let playerItem: any AVPlayableItem
  let isPlayable: Bool
  let duration: CMTime
}
