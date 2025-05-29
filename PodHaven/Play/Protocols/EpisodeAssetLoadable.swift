// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@MainActor
struct EpisodeAsset: Sendable {
  let playerItem: any AVPlayableItem
  let duration: CMTime
  let isPlayable: Bool

  static func equals(_ lhs: (any AVPlayableItem)?, _ rhs: (any AVPlayableItem)?) -> Bool {
    lhs?.assetURL == rhs?.assetURL
  }
}

protocol EpisodeAssetLoadable: Sendable {
  func load(for url: URL) async throws -> EpisodeAsset
}

struct AVFoundationEpisodeAssetLoader: EpisodeAssetLoadable {
  func load(for url: URL) async throws -> EpisodeAsset {
    let asset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
    return await EpisodeAsset(
      playerItem: AVPlayerItem(asset: asset),
      duration: duration,
      isPlayable: isPlayable
    )
  }
}
