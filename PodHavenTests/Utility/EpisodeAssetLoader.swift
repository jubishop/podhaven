// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var episodeAssetLoader: Factory<EpisodeAssetLoader> {
    Factory(self) { EpisodeAssetLoader() }.scope(.cached)
  }
}

class EpisodeAssetLoader {
  var responseCounts: [MediaURL: Int] = [:]

  private var fakeHandlers: [MediaURL: @Sendable (MediaURL) async throws -> (Bool, CMTime)] = [:]

  func respond(
    to mediaURL: MediaURL,
    delay: Duration? = nil,
    _ handler: @Sendable @escaping (MediaURL) async throws -> (Bool, CMTime)
  ) {
    fakeHandlers[mediaURL] = { mediaURL in
      if let delay { try await Task.sleep(for: delay) }
      return try await handler(mediaURL)
    }
  }

  func clearCustomHandler(for mediaURL: MediaURL) {
    fakeHandlers.removeValue(forKey: mediaURL)
  }

  func loadEpisodeAsset(_ mediaURL: MediaURL) async throws -> EpisodeAsset {
    if let handler = fakeHandlers[mediaURL] {
      defer { responseCounts[mediaURL, default: 0] += 1 }
      let (isPlayable, duration) = try await handler(mediaURL)
      return await EpisodeAsset(
        playerItem: FakeAVPlayerItem(assetURL: mediaURL),
        isPlayable: isPlayable,
        duration: duration
      )
    }

    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(assetURL: mediaURL),
      isPlayable: true,
      duration: CMTime.inSeconds(60)
    )
  }
}
