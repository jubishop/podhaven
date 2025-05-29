// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

struct EpisodeAsset {
  let playerItem: AVPlayerItem
  let duration: CMTime
  let isPlayable: Bool
}

protocol EpisodeAssetLoadable: Sendable {
  func load(for url: URL) async throws -> EpisodeAsset
}

struct AVFoundationEpisodeAssetLoader: EpisodeAssetLoadable {
  func load(for url: URL) async throws -> EpisodeAsset {
    let asset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await asset.load(.isPlayable, .duration)
    return EpisodeAsset(
      playerItem: AVPlayerItem(asset: asset),
      duration: duration,
      isPlayable: isPlayable
    )
  }
}
