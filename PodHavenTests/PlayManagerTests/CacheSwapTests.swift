// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("Active stream cache swaps", .container)
@MainActor struct CacheSwapTests {
  enum Trigger: CaseIterable {
    case pause, buffering, seek
  }

  init() {
    Container.shared.stateManager().start()
    Container.shared.cacheManager().start()
    PlayHelpers.setupCommandHandling()
  }

  private func streaming() async throws -> (PodcastEpisode, FakeAVPlayer) {
    let episode = try await Create.podcastEpisode()
    try await Container.shared.playManager().play(episode)
    try await PlayHelpers.waitFor(.playing)
    let player = try #require(Container.shared.avPlayer() as? FakeAVPlayer)
    player.resetTimeOnReplacement = true
    player.advanceTime(to: .seconds(12))
    try await PlayHelpers.waitFor(.seconds(12))
    await Container.shared.playManager().setRate(1.5)
    let task = try await CacheHelpers.waitForDownloadTask(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    _ = try await CacheHelpers.waitForCached(episode.id)
    return (try #require(try await Container.shared.repo().podcastEpisode(episode.id)), player)
  }

  @Test("remote fallback preserves the active item and transport", arguments: Trigger.allCases)
  func remoteFallbackPreservesStream(trigger: Trigger) async throws {
    try await LogCapture.withSink { sink in
      let (episode, player) = try await streaming()
      let cachedURL = try #require(episode.episode.cachedURL)
      let originalItem = try #require(player.current)
      let podPlayer = Container.shared.podAVPlayer()
      let originalSource = podPlayer.playbackSnapshot().source
      let originalSeeks = player.seekRequests.count
      let loader = Container.shared.fakeEpisodeAssetLoader()
      let cachedLoads = await loader.responseCount(for: cachedURL)
      let remoteLoads = await loader.responseCount(for: episode.episode.mediaURL)
      await loader.respond(to: cachedURL, error: TestError.assetLoadFailure(episode))

      switch trigger {
      case .pause:
        await Container.shared.playManager().pause()
      case .buffering:
        player.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      case .seek:
        await Container.shared.playManager().seek(to: .seconds(20))
      }
      try await Wait.until {
        sink.captured()
          .contains {
            $0.message == "swapToCached: swapped to cached version"
              || $0.message
                == "swapToCached: keeping active stream because loaded item is not local"
          }
      } _: {
        "Cache swap did not finish"
      }
      if trigger == .seek {
        try await PlayHelpers.waitFor(.seconds(20))
        try await PlayHelpers.waitForPeriodicTimeObserver()
      }

      #expect(player.current === originalItem)
      #expect(podPlayer.playbackSnapshot().source == originalSource)
      #expect(player.currentTime() == .seconds(trigger == .seek ? 20 : 12))
      #expect(player.seekRequests.count == originalSeeks + (trigger == .seek ? 1 : 0))
      #expect(player.rate == (trigger == .pause ? 0 : 1.5))
      switch trigger {
      case .pause: #expect(player.timeControlStatus == .paused)
      case .buffering:
        #expect(player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        #expect(player.reasonForWaitingToPlay == .evaluatingBufferingRate)
      case .seek: #expect(player.timeControlStatus == .playing)
      }
      #expect(!sink.captured().contains { $0.message == "swapToCached: swapped to cached version" })
      #expect(try await Container.shared.repo().episode(episode.id)?.cachedURL == nil)
      let files = try #require(Container.shared.fileManager() as? FakeFileManager)
      #expect(!files.fileExists(at: cachedURL.rawValue))
      try await CacheHelpers.waitForDownloading(episode.id)
      _ = try await CacheHelpers.waitForDownloadTask(episode.id)
      #expect(await loader.responseCount(for: cachedURL) == cachedLoads + 1)
      #expect(await loader.responseCount(for: episode.episode.mediaURL) == remoteLoads + 1)

      await Container.shared.playManager().seek(to: .seconds(24))
      try await PlayHelpers.waitFor(.seconds(24))
      try await PlayHelpers.waitForPeriodicTimeObserver()
      #expect(player.current === originalItem)
      #expect(await loader.responseCount(for: cachedURL) == cachedLoads + 1)
      #expect(await loader.responseCount(for: episode.episode.mediaURL) == remoteLoads + 1)
    }
  }

  @Test("a pause during failed cache loading preserves the pending manual seek")
  func pauseDuringManualSeek() async throws {
    let (episode, player) = try await streaming()
    let cachedURL = try #require(episode.episode.cachedURL)
    let originalItem = try #require(player.current)
    let loadStarted = AsyncSemaphore(value: 0)
    let finishLoad = AsyncSemaphore(value: 0)
    let seekStarted = AsyncSemaphore(value: 0)
    let finishSeek = AsyncSemaphore(value: 0)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: cachedURL) { _ in
        loadStarted.signal()
        await finishLoad.wait()
        throw TestError.assetLoadFailure(episode)
      }
    player.seekHandler = { _ in
      seekStarted.signal()
      await finishSeek.wait()
      return true
    }
    let seek = Task { await Container.shared.playManager().seek(to: .seconds(20)) }
    defer {
      seek.cancel()
      finishLoad.signal()
      finishSeek.signal()
    }
    await loadStarted.wait()
    await Container.shared.playManager().pause()
    finishLoad.signal()
    await seek.value
    await seekStarted.wait()

    #expect(player.current === originalItem)
    #expect(player.currentTime() == .seconds(12))
    #expect(player.timeControlStatus == .paused)
    #expect(player.seekRequests.last == .seconds(20))
    finishSeek.signal()
    try await PlayHelpers.waitForPeriodicTimeObserver()
    #expect(player.currentTime() == .seconds(20))
    #expect(player.timeControlStatus == .paused)
    #expect(try await Container.shared.repo().episode(episode.id)?.currentTime == .seconds(20))
  }

  @Test("valid local swaps still work when optional silence metadata fails")
  func localSwapWithoutSilenceMetadata() async throws {
    try await LogCapture.withSink { sink in
      let (episode, player) = try await streaming()
      let cachedURL = try #require(episode.episode.cachedURL)
      let originalItem = try #require(player.current)
      try await Container.shared.appDB().unsafeTestDB
        .write { db in
          try db.execute(sql: "DELETE FROM cachedAudioContent")
          try db.execute(
            sql: """
              CREATE TEMP TRIGGER fail_swap_metadata BEFORE INSERT ON cachedAudioContent
              BEGIN SELECT RAISE(ABORT, 'metadata unavailable'); END
              """
          )
        }

      await Container.shared.playManager().seek(to: .seconds(20))
      try await PlayHelpers.waitForCurrentItem(cachedURL)
      try await PlayHelpers.waitForPeriodicTimeObserver()

      #expect(player.current !== originalItem)
      #expect(player.currentTime() == .seconds(20))
      #expect(player.timeControlStatus == .playing)
      #expect(player.rate == 1.5)
      #expect(try await Container.shared.repo().episode(episode.id)?.cachedURL == cachedURL)
      #expect(sink.captured().contains { $0.message.contains("Silence metadata unavailable") })
      #expect(sink.captured().contains { $0.message == "swapToCached: swapped to cached version" })
    }
  }
}
