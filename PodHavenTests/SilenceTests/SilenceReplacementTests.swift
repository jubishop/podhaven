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

  @Test(
    "a download that finishes during playback switches sources at the next pause",
    arguments: ["user", "system"]
  )
  func switchAtPause(pause: String) async throws {
    Container.shared.userSettings().$silenceMode.new(.gentle)
    try await LogCapture.withSink { sink in
      let episode = try await Create.podcastEpisode()
      let manager = Container.shared.playManager()
      try await manager.play(episode)
      try await PlayHelpers.waitFor(.playing)
      let player = Container.shared.avPlayer() as! FakeAVPlayer
      player.resetTimeOnReplacement = true
      player.advanceTime(to: .seconds(12))
      await manager.setRate(1.5)
      let streamingItem = try #require(player.current)
      let pauses = player.pauseCallCount
      let task = try await CacheHelpers.waitForDownloadTask(episode.id)
      try await CacheHelpers.simulateBackgroundFinish(task)
      let url = try await CacheHelpers.waitForCached(episode.id)
      let store = Container.shared.silenceStore()
      let content = try #require(try await store.content(for: url.lastPathComponent))
      let interval = QuietInterval(start: 16, end: 25)
      try await store.publish(
        SilenceMap(duration: 30, high: [interval], medium: [interval], low: [interval]),
        for: content
      )
      try await Wait.until(maxAttempts: 200) { @MainActor in
        player.current !== streamingItem
          || sink.captured()
            .contains { $0.message.hasPrefix("activateCachedSilence: waiting for a pause") }
      } _: {
        "The finished download was not considered for silence shortening"
      }
      #expect(player.current === streamingItem)
      #expect(player.timeControlStatus == .playing)
      #expect(player.pauseCallCount == pauses)
      #expect(player.preciseSeekRequests.isEmpty)

      if pause == "user" {
        await manager.pause()
      } else {
        player.pause()
      }
      try await Wait.until(maxAttempts: 200) { @MainActor in
        Container.shared.podAVPlayer().playbackSnapshot().isFromCache
          && player.completedSeekCount == 1
      } _: {
        "Pausing did not switch to the downloaded file"
      }
      try await PlayHelpers.waitForPeriodicTimeObserver()
      let restoration = try #require(player.preciseSeekRequests.first)
      #expect(restoration.0 == .seconds(12))
      #expect(restoration.1 == .zero)
      #expect(restoration.2 == .zero)
      #expect(player.currentTime() == .seconds(12))
      #expect(player.timeControlStatus == .paused)

      (player.current as! FakeAVPlayerItem).setStatus(.readyToPlay)
      await manager.play()
      try await PlayHelpers.waitFor(.playing)
      #expect(player.rate == 1.5)
      player.advanceTime(to: .seconds(17))
      try await Wait.until(maxAttempts: 200) { @MainActor in
        player.preciseSeekRequests.count == 2
      } _: {
        "Silence shortening did not start after playback resumed"
      }
      let cut = try #require(player.preciseSeekRequests.last)
      #expect(abs(cut.0.seconds - (25 - 0.3 / sqrt(1.5))) < 0.001)
    }
  }

  @Test("a download that finishes while paused switches sources without resuming")
  func switchWhilePaused() async throws {
    Container.shared.userSettings().$silenceMode.new(.gentle)
    let episode = try await Create.podcastEpisode()
    let manager = Container.shared.playManager()
    try await manager.load(episode)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    player.resetTimeOnReplacement = true
    await manager.seek(to: .seconds(12))
    try await PlayHelpers.waitFor(.seconds(12))
    try await PlayHelpers.waitForPeriodicTimeObserver()
    await manager.setRate(1.5)
    let task = try await CacheHelpers.waitForDownloadTask(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    _ = try await CacheHelpers.waitForCached(episode.id)
    try await Wait.until(maxAttempts: 200) { @MainActor in
      Container.shared.podAVPlayer().playbackSnapshot().isFromCache
        && player.completedSeekCount == 2
    } _: {
      "The finished download did not replace the paused stream"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    let restoration = try #require(player.preciseSeekRequests.first)
    #expect(player.preciseSeekRequests.count == 1)
    #expect(restoration.0 == .seconds(12))
    #expect(restoration.1 == .zero)
    #expect(restoration.2 == .zero)
    #expect(player.currentTime() == .seconds(12))
    #expect(player.timeControlStatus == .paused)
    #expect(player.playCallCount == 0)
    #expect(player.defaultRate == 1.5)
  }

  @Test("failed cache positioning restores streaming and suppresses automatic retry")
  func failedReplacement() async throws {
    let (episode, player) = try await streaming()
    player.seekHandler = { _ in
      !(player.current as! FakeAVPlayerItem).url.isFileURL
    }
    PlayBarViewModel().selectQuietAudioProtection(.low)
    PlayBarViewModel().selectSilenceMode(.balanced)
    await Container.shared.playManager().pause()
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.completedSeekCount >= 2
        && !Container.shared.podAVPlayer().playbackSnapshot().isFromCache
    } _: {
      "Failed local positioning did not restore streaming"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    #expect(player.currentTime() == .seconds(12))
    #expect(player.defaultRate == 1.5)
    #expect(Container.shared.sharedState().silenceOverride?.mode == .balanced)
    #expect(PlayBarViewModel().quietAudioProtection == .low)
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
    arguments: ["off", "pause", "toggle", "doubleToggle", "evict"]
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
    await Container.shared.playManager().pause()
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.preciseSeekRequests.count == 1
    } _: {
      "Replacement did not start"
    }
    if action == "pause" {
      await Container.shared.playManager().pause()
    } else if action == "toggle" || action == "doubleToggle" {
      await Container.shared.playManager().toggle()
      if action == "doubleToggle" { await Container.shared.playManager().toggle() }
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
    #expect(player.timeControlStatus == (action == "toggle" ? .playing : .paused))
  }

  @Test("failure to restore streaming stays paused and presents the playback error")
  func failedStreamingRestoration() async throws {
    let (_, player) = try await streaming()
    player.seekHandler = { _ in false }
    PlayBarViewModel().selectQuietAudioProtection(.low)
    PlayBarViewModel().selectSilenceMode(.balanced)
    await Container.shared.playManager().pause()
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
    PlayBarViewModel().selectQuietAudioProtection(.low)
    PlayBarViewModel().selectSilenceMode(.balanced)
    await Container.shared.playManager().pause()
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
    PlayBarViewModel().selectQuietAudioProtection(.low)
    PlayBarViewModel().selectSilenceMode(.balanced)
    await Container.shared.playManager().pause()
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
