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
  private var fakeHandlers: [URL: @Sendable (URL) async throws -> (Bool, CMTime)] = [:]

  func respond(
    to url: URL,
    delay: Duration? = nil,
    _ handler: @Sendable @escaping (URL) async throws -> (Bool, CMTime)
  ) {
    fakeHandlers[url] = { url in
      if let delay { try await Task.sleep(for: delay) }
      return try await handler(url)
    }
  }

  func loadEpisodeAsset(_ url: URL) async throws -> EpisodeAsset {
    if let handler = fakeHandlers[url] {
      let (isPlayable, duration) = try await handler(url)
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
