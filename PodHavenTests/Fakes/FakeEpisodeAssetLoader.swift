// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeEpisodeAssetLoader: Factory<FakeEpisodeAssetLoader> {
    Factory(self) { FakeEpisodeAssetLoader() }.scope(.cached)
  }
}

class FakeEpisodeAssetLoader {
  typealias LoadHandler = @Sendable (URL) async throws -> (Bool, CMTime)

  private var responseCounts: [URL: Int] = [:]
  func responseCount(for podcastEpisode: PodcastEpisode) -> Int {
    responseCount(for: podcastEpisode.episode.mediaURL)
  }
  func responseCount(for url: URL) -> Int {
    responseCounts[url, default: 0]
  }

  private var defaultHandler: LoadHandler = { _ in
    (true, CMTime.seconds(Double.random(in: 1...999)))
  }
  private var fakeHandlers: [URL: LoadHandler] = [:]

  func setDefaultResponse(_ handler: @escaping LoadHandler) {
    defaultHandler = handler
  }

  func respond(to episode: Episode, _ handler: @escaping LoadHandler) {
    respond(to: episode.mediaURL, handler)
  }
  func respond(to url: URL, _ handler: @escaping LoadHandler) {
    fakeHandlers[url] = handler
  }

  func clearCustomHandler(for episode: Episode) {
    fakeHandlers.removeValue(forKey: episode.mediaURL)
  }

  func loadEpisodeAsset(_ asset: AVURLAsset) async throws -> EpisodeAsset {
    defer { responseCounts[asset.url, default: 0] += 1 }

    let handler = fakeHandlers[asset.url, default: defaultHandler]
    let (isPlayable, duration) = try await handler(asset.url)
    try Task.checkCancellation()
    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(url: asset.url),
      isPlayable: isPlayable,
      duration: duration
    )
  }
}
