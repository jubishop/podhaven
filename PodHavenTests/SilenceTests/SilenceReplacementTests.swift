// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("Silence source replacement", .container)
@MainActor struct SilenceReplacementTests {
  init() {
    Container.shared.stateManager().start()
    Container.shared.cacheManager().start()
    PlayHelpers.setupCommandHandling()
  }

  private func streaming() async throws -> (PodcastEpisode, FakeAVPlayer) {
    let episode = try await Create.podcastEpisode()
    try await Container.shared.playManager().play(episode)
    try await PlayHelpers.waitFor(.playing)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    player.resetTimeOnReplacement = true
    player.advanceTime(to: .seconds(12))
    await Container.shared.playManager().setRate(1.5)
    let task = try await CacheHelpers.waitForDownloadTask(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    _ = try await CacheHelpers.waitForCached(episode.id)
    return (episode, player)
  }

  @Test("failed cache positioning restores streaming and suppresses automatic retry")
  func failedReplacement() async throws {
    let (episode, player) = try await streaming()
    player.seekHandler = { _ in
      !(player.current as! FakeAVPlayerItem).url.isFileURL
    }
    PlayBarViewModel().selectSilenceMode(.balanced)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.completedSeekCount >= 2
        && !Container.shared.podAVPlayer().playbackSnapshot().isFromCache
    } _: {
      "Failed local positioning did not restore streaming"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    #expect(player.currentTime() == .seconds(12))
    #expect(player.rate == 1.5)
    #expect(Container.shared.sharedState().silenceOverride?.mode == .balanced)
    await Container.shared.playManager().pause()
    await Container.shared.playManager().play()
    player.advanceTime(to: .seconds(15))
    try await PlayHelpers.waitFor(.seconds(15))
    #expect(!Container.shared.podAVPlayer().playbackSnapshot().isFromCache)
    #expect(player.preciseSeekRequests.count == 2)
    #expect(try await Container.shared.repo().episode(episode.id)?.currentTime == .seconds(15))
  }

  @Test(
    "controls and cache eviction preserve replacement position",
    arguments: ["off", "pause", "evict"]
  )
  func controlsDuringReplacement(action: String) async throws {
    let (_, player) = try await streaming()
    let release = AsyncSemaphore(value: 0)
    player.seekHandler = { _ in
      await release.wait()
      return true
    }
    defer { release.signal() }
    let viewModel = PlayBarViewModel()
    viewModel.selectSilenceMode(.balanced)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.preciseSeekRequests.count == 1
    } _: {
      "Replacement did not start"
    }
    if action == "pause" {
      await Container.shared.playManager().pause()
    } else if action == "evict" {
      try await Container.shared.appDB().unsafeTestDB
        .write { db in
          try db.execute(sql: "DELETE FROM cachedAudioContent")
        }
      Container.shared.userSettings().$silenceMode.new(.off)
    } else {
      viewModel.selectSilenceMode(.off)
      Container.shared.userSettings().$silenceMode.new(.off)
    }
    release.signal()
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.completedSeekCount == 1
    } _: {
      "Replacement did not finish"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    #expect(player.currentTime() == .seconds(12))
    #expect(player.timeControlStatus == (action == "pause" ? .paused : .playing))
  }

  @Test("failure to restore streaming stays paused and presents the playback error")
  func failedStreamingRestoration() async throws {
    let (_, player) = try await streaming()
    player.seekHandler = { _ in false }
    PlayBarViewModel().selectSilenceMode(.balanced)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      Container.shared.alert().config != nil
    } _: {
      "Failed streaming restoration did not present an error"
    }
    #expect(player.timeControlStatus == .paused)
    #expect(!Container.shared.podAVPlayer().playbackSnapshot().isFromCache)
    #expect(player.preciseSeekRequests.count == 2)
  }

  @Test("same-playback media recovery does not retry a rejected local source")
  func rejectedRecovery() async throws {
    let (_, player) = try await streaming()
    player.seekHandler = { _ in !(player.current as! FakeAVPlayerItem).url.isFileURL }
    PlayBarViewModel().selectSilenceMode(.balanced)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.completedSeekCount >= 2
        && !Container.shared.podAVPlayer().playbackSnapshot().isFromCache
    } _: {
      "Failed local positioning did not restore streaming"
    }
    Container.shared.notifier().continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await Wait.until(maxAttempts: 200) { @MainActor in
      (Container.shared.avPlayer() as! FakeAVPlayer) != player
    } _: {
      "Media recovery did not replace the player"
    }
    try await PlayHelpers.waitFor(.stopped)
    await Container.shared.playManager().play()
    try await PlayHelpers.waitFor(.playing)
    #expect(!Container.shared.podAVPlayer().playbackSnapshot().isFromCache)
  }

  @Test("a manual seek supersedes replacement without a late position change")
  func manualDuringReplacement() async throws {
    let (_, player) = try await streaming()
    let release = AsyncSemaphore(value: 0)
    player.seekHandler = { time in
      if time == .seconds(12) { await release.wait() }
      return true
    }
    defer { release.signal() }
    PlayBarViewModel().selectSilenceMode(.balanced)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.preciseSeekRequests.count == 1
    } _: {
      "Replacement did not start"
    }
    await Container.shared.playManager().seek(to: .seconds(20))
    try await PlayHelpers.waitFor(.seconds(20))
    release.signal()
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.completedSeekCount == 2
    } _: {
      "Cancelled replacement did not complete"
    }
    #expect(player.currentTime() == .seconds(20))
  }
}
