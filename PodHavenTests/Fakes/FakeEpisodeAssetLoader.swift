// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation

@testable import PodHaven

actor FakeEpisodeAssetLoader {
  private static var fakeHandlers: [URL: @Sendable (URL) async throws -> (Bool, CMTime)] = [:]

  static func respond(
    to url: URL,
    delay: Duration? = nil,
    _ handler: @Sendable @escaping (URL) async throws -> (Bool, CMTime)
  ) {
    fakeHandlers[url] = { url in
      if let delay { try await Task.sleep(for: delay) }
      return try await handler(url)
    }
  }

  static func loadEpisodeAsset(_ url: URL) async throws -> EpisodeAsset {
    guard let handler = fakeHandlers[url]
    else { Assert.fatal("No handler for \(url)??") }

    let (isPlayable, duration) = try await handler(url)
    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(assetURL: url),
      isPlayable: isPlayable,
      duration: duration
    )
  }
}
