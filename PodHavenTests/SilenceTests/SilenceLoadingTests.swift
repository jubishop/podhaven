// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("Silence metadata load cancellation", .container)
@MainActor struct SilenceLoadingTests {
  @Test("cancelled content lookup does not start loading the cached asset")
  func cancelledContentLookup() async throws {
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: "cancelled-content.mp3")
    )
    let url = try #require(episode.episode.cachedURL)
    let player = Container.shared.podAVPlayer()
    let task = Task { try await player.load(episode) }
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await Container.shared.fakeEpisodeAssetLoader().responseCount(for: url) == 0)
    #expect(player.playbackSnapshot().episodeID == nil)
    #expect(try await Container.shared.repo().episode(episode.id)?.cachedURL == url)
  }

  @Test("cancelled identity validation does not continue to duration persistence")
  func cancelledIdentityValidation() async throws {
    let episode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: "cancelled-identity.mp3")
    )
    let url = try #require(episode.episode.cachedURL)
    let fileManager = Container.shared.fileManager() as! FakeFileManager
    try await fileManager.writeData(Data("cached audio".utf8), to: url.rawValue)
    let (started, continuation) = AsyncStream<Void>.makeStream()
    let release = AsyncSemaphore(value: 0)
    Container.shared.loadEpisodeAsset.context(.test) {
      { @concurrent url in
        let asset = await EpisodeAsset(
          isPlayable: true,
          duration: .seconds(30),
          playerItemFactory: { FakeAVPlayerItem(url: url) }
        )
        continuation.yield()
        await release.wait()
        return asset
      }
    }
    let player = Container.shared.podAVPlayer()
    let repo = Container.shared.repo() as! FakeRepo
    let task = Task { try await player.load(episode) }
    defer {
      task.cancel()
      release.signal()
      continuation.finish()
    }
    for await _ in started { break }
    task.cancel()
    release.signal()

    await #expect(throws: CancellationError.self) { try await task.value }
    try repo.expectNoCall(methodName: "updateDuration")
    #expect(player.playbackSnapshot().episodeID == nil)
    #expect(try await repo.episode(episode.id)?.cachedURL == url)
  }
}
