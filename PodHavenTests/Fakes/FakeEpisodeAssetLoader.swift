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
  func responseCount<T: RawRepresentable>(for taggedURL: T) -> Int where T.RawValue == URL {
    responseCounts[taggedURL.rawValue, default: 0]
  }

  private var defaultHandler: LoadHandler = { _ in
    (true, CMTime.seconds(Double.random(in: 1...999)))
  }
  private var fakeHandlers: [URL: LoadHandler] = [:]

  func setDefaultHandler(_ handler: @escaping LoadHandler) {
    defaultHandler = handler
  }

  func respond<T: RawRepresentable>(to taggedURL: T, _ handler: @escaping LoadHandler)
  where T.RawValue == URL {
    fakeHandlers[taggedURL.rawValue] = handler
  }

  func respond<T: RawRepresentable>(to taggedURL: T, data: ResponseData) where T.RawValue == URL {
    respond(to: taggedURL) { episode in data }
  }

  func respond<T: RawRepresentable>(to taggedURL: T, error: Error) where T.RawValue == URL {
    respond(to: taggedURL) { _ in throw error }
  }

  func waitThenRespond<T: RawRepresentable>(
    to taggedURL: T,
    data: ResponseData = (true, CMTime.seconds(Double.random(in: 1...999)))
  ) async -> AsyncSemaphore where T.RawValue == URL {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: taggedURL) { episode in
      try await asyncSemaphore.waitUnlessCancelled()
      return data
    }
    return asyncSemaphore
  }

  func waitThenRespond<T: RawRepresentable>(
    to taggedURL: T,
    error: Error
  ) async -> AsyncSemaphore where T.RawValue == URL {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: taggedURL) { episode in
      try await asyncSemaphore.waitUnlessCancelled()
      throw error
    }
    return asyncSemaphore
  }

  func clearCustomHandler(for episode: Episode) {
    fakeHandlers.removeValue(forKey: episode.mediaURL.rawValue)
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
