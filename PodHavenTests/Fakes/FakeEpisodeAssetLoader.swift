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
  typealias LoadHandler = @Sendable (Episode) async throws -> (Bool, CMTime)

  private var responseCounts: [Episode.ID: Int] = [:]
  func responseCount(for podcastEpisode: PodcastEpisode) -> Int {
    responseCounts[podcastEpisode.id, default: 0]
  }

  private var defaultHandler: LoadHandler = { _ in
    (true, CMTime.seconds(Double.random(in: 1...999)))
  }
  private var fakeHandlers: [Episode.ID: LoadHandler] = [:]

  func setDefaultResponse(_ handler: @escaping LoadHandler) {
    defaultHandler = handler
  }

  func respond(to episode: Episode, _ handler: @escaping LoadHandler) {
    fakeHandlers[episode.id] = handler
  }

  func clearCustomHandler(for episode: Episode) {
    fakeHandlers.removeValue(forKey: episode.id)
  }

  func loadEpisodeAsset(_ episode: Episode) async throws -> EpisodeAsset {
    defer { responseCounts[episode.id, default: 0] += 1 }

    let handler = fakeHandlers[episode.id, default: defaultHandler]
    let (isPlayable, duration) = try await handler(episode)
    try Task.checkCancellation()
    return await EpisodeAsset(
      playerItem: FakeAVPlayerItem(episode: episode),
      isPlayable: isPlayable,
      duration: duration
    )
  }
}
