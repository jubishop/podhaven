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
  typealias LoadHandler = @Sendable (MediaURL) async throws -> (Bool, CMTime)

  private(set) var responseCounts: [MediaURL: Int] = [:]

  private var defaultHandler: LoadHandler = { _ in (true, CMTime.inSeconds(60)) }
  private var fakeHandlers: [MediaURL: LoadHandler] = [:]

  func setDefaultResponse(_ handler: @escaping LoadHandler) {
    defaultHandler = handler
  }

  func respond(to mediaURL: MediaURL, _ handler: @escaping LoadHandler) {
    fakeHandlers[mediaURL] = handler
  }

  func clearCustomHandler(for mediaURL: MediaURL) {
    fakeHandlers.removeValue(forKey: mediaURL)
  }

  func loadEpisodeAsset(_ mediaURL: MediaURL) async throws -> EpisodeAsset {
    defer { responseCounts[mediaURL, default: 0] += 1 }

    let handler = fakeHandlers[mediaURL, default: defaultHandler]
    let (isPlayable, duration) = try await handler(mediaURL)
    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(assetURL: mediaURL),
      isPlayable: isPlayable,
      duration: duration
    )
  }
}
