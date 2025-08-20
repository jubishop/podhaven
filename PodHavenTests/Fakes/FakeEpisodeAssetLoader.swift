// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Semaphore

@testable import PodHaven

extension Container {
  var fakeEpisodeAssetLoader: Factory<FakeEpisodeAssetLoader> {
    Factory(self) { FakeEpisodeAssetLoader() }.scope(.cached)
  }
}

actor FakeEpisodeAssetLoader {
  typealias ResponseData = (Bool, CMTime)
  typealias LoadHandler = @Sendable (URL) async throws -> ResponseData

  private(set) var totalResponseCounts = 0
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

  func setDefaultHandler(_ handler: @escaping LoadHandler) {
    defaultHandler = handler
  }

  func respond(to episode: Episode, _ handler: @escaping LoadHandler) {
    fakeHandlers[episode.mediaURL] = handler
  }

  func respond(to episode: Episode, data: ResponseData) {
    respond(to: episode) { episode in data }
  }

  func respond(to episode: Episode, error: Error) {
    respond(to: episode) { _ in throw error }
  }

  func waitThenRespond(
    to episode: Episode,
    data: ResponseData = (true, CMTime.seconds(Double.random(in: 1...999)))
  ) async
    -> AsyncSemaphore
  {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: episode) { episode in
      try await asyncSemaphore.waitUnlessCancelled()
      return data
    }
    return asyncSemaphore
  }

  func waitThenRespond(
    to episode: Episode,
    error: Error
  ) async
  -> AsyncSemaphore
  {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: episode) { episode in
      try await asyncSemaphore.waitUnlessCancelled()
      throw error
    }
    return asyncSemaphore
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
