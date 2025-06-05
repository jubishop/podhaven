// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import FactoryKit

@testable import PodHaven

extension Container {
  var episodeAssetLoader: Factory<EpisodeAssetLoader> {
    Factory(self) { EpisodeAssetLoader() }.scope(.cached)
  }
}

class EpisodeAssetLoader {
  private var fakeHandlers: [MediaURL: @Sendable (MediaURL) async throws -> (Bool, CMTime)] = [:]

  func respond(
    to url: MediaURL,
    delay: Duration? = nil,
    _ handler: @Sendable @escaping (MediaURL) async throws -> (Bool, CMTime)
  ) {
    fakeHandlers[url] = { url in
      if let delay { try await Task.sleep(for: delay) }
      return try await handler(url)
    }
  }

  func loadEpisodeAsset(_ url: URL) async throws -> EpisodeAsset {
    let mediaURL = MediaURL(rawValue: url)
    if let handler = fakeHandlers[mediaURL] {
      let (isPlayable, duration) = try await handler(mediaURL)
      return await EpisodeAsset(
        playerItem: FakeAVPlayerItem(assetURL: url),
        isPlayable: isPlayable,
        duration: duration
      )
    }

    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(assetURL: url),
      isPlayable: true,
      duration: CMTime.inSeconds(60)
    )
  }
}
