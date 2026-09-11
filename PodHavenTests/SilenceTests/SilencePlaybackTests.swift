// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("Silence playback", .container)
@MainActor struct SilencePlaybackTests {
  init() {
    Container.shared.stateManager().start()
    Container.shared.cacheManager().start()
    PlayHelpers.setupCommandHandling()
  }

  @Test("downloaded silence advances source time automatically")
  func automaticCut() async throws {
    let episode = try await Create.podcastEpisode()
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    let url = try await CacheHelpers.waitForCached(episode.id)
    let store = Container.shared.silenceStore()
    let content = try #require(try await store.content(for: url.lastPathComponent))
    try await store.publish(
      SilenceMap(duration: 30, intervals: [.init(start: 1, end: 4)]),
      for: content
    )
    Container.shared.userSettings().$silenceMode.new(.gentle)
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    try await Container.shared.playManager().play(loaded)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    (player.current as! FakeAVPlayerItem).setStatus(.readyToPlay)
    try await PlayHelpers.waitForPeriodicTimeObserver()
    player.advanceTime(to: .seconds(1.5))
    try await Wait.until(maxAttempts: 100) {
      await MainActor.run { player.seekRequests.contains { abs($0.seconds - 3.7) < 0.001 } }
    } _: {
      "No automatic cut to the protected end of the quiet interval"
    }
    try await PlayHelpers.waitFor(.seconds(3.7))
  }

  @Test("selecting another episode clears the temporary mode")
  func resetOnNewEpisode() async throws {
    let (first, second) = try await Create.twoPodcastEpisodes()
    let manager = Container.shared.playManager()
    try await manager.load(first)
    let state = Container.shared.sharedState()
    state.$silenceOverride.new(SilenceOverride(episodeID: first.id, mode: .aggressive))
    try await manager.load(second)
    #expect(state.silenceOverride == nil)
  }

  @Test("finishing with Stop After Current Episode clears the temporary playback mode")
  func resetOnFinish() async throws {
    let (_, player) = try await prepared()
    PlayBarViewModel().selectSilenceMode(.aggressive)
    let state = Container.shared.sharedState()
    state.setStopAfterCurrentEpisode(true)
    await Container.shared.playManager().play()
    try await PlayHelpers.waitFor(.playing)
    player.finishEpisode()
    try await Wait.until(maxAttempts: 200) {
      state.currentEpisodeID == nil && state.playbackStatus == .stopped
    } _: {
      "Stop After Current Episode did not finish playback"
    }
    #expect(state.silenceOverride == nil)
    #expect(state.silenceSourceRejection == nil)
  }

  private func prepared(_ interval: QuietInterval = .init(start: 1, end: 10)) async throws
    -> (PodcastEpisode, FakeAVPlayer)
  {
    let episode = try await Create.podcastEpisode()
    let task = try await CacheHelpers.downloadToCache(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(task)
    let url = try await CacheHelpers.waitForCached(episode.id)
    let store = Container.shared.silenceStore()
    let content = try #require(try await store.content(for: url.lastPathComponent))
    try await store.publish(SilenceMap(duration: 30, intervals: [interval]), for: content)
    Container.shared.userSettings().$silenceMode.new(.gentle)
    let loaded = try #require(try await Container.shared.repo().podcastEpisode(episode.id))
    try await Container.shared.playManager().load(loaded)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    (player.current as! FakeAVPlayerItem).setStatus(.readyToPlay)
    return (loaded, player)
  }

  @Test("a paused manual landing waits for resume and uses the selected rate")
  func pausedManualLanding() async throws {
    let (_, player) = try await prepared()
    let manager = Container.shared.playManager()
    await manager.setRate(2)
    await manager.seek(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    #expect(player.preciseSeekRequests.isEmpty)
    await manager.play()
    let target = 10 - 0.3 / sqrt(2)
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { abs(player.currentTime().seconds - target) < 0.001 }
    } _: {
      "Resume did not shorten the remaining silence at the selected speed"
    }
    #expect(player.preciseSeekRequests.last?.1 == .zero)
    #expect(player.preciseSeekRequests.last?.2 == .zero)
    await manager.seek(to: .seconds(5))
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { player.preciseSeekRequests.count == 2 }
    } _: {
      "Manual reentry should allow a new cut in the same interval"
    }
  }

  @Test("Off cancels a pending automatic seek without moving to its target")
  func disablePendingCut() async throws {
    let (_, player) = try await prepared()
    let release = AsyncSemaphore(value: 0)
    player.seekHandler = { _ in
      await release.wait()
      return true
    }
    defer { release.signal() }
    await Container.shared.playManager().play()
    player.advanceTime(to: .seconds(2))
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { !player.preciseSeekRequests.isEmpty }
    } _: {
      "Automatic seek was not requested"
    }
    Container.shared.userSettings().$silenceMode.new(.off)
    try await PlayHelpers.waitForPeriodicTimeObserver()
    release.signal()
    player.advanceTime(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    #expect(player.currentTime().seconds == 3)
    #expect(player.preciseSeekRequests.count == 1)
  }

  @Test("manual transport supersedes pending automatic work")
  func manualPrecedence() async throws {
    let (_, player) = try await prepared()
    let release = AsyncSemaphore(value: 0)
    player.seekHandler = { time in
      if time.seconds < 10 { await release.wait() }
      return true
    }
    defer { release.signal() }
    let manager = Container.shared.playManager()
    await manager.play()
    player.advanceTime(to: .seconds(2))
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { !player.preciseSeekRequests.isEmpty }
    } _: {
      "Automatic seek was not requested"
    }
    await manager.seek(to: .seconds(20))
    try await PlayHelpers.waitFor(.seconds(20))
    release.signal()
    #expect(player.currentTime().seconds == 20)
    #expect(player.preciseSeekRequests.count == 1)
  }

  @Test("a failed automatic seek restores time observation and does not repeat")
  func failedCut() async throws {
    let (_, player) = try await prepared()
    player.seekHandler = { _ in false }
    await Container.shared.playManager().play()
    player.advanceTime(to: .seconds(2))
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { !player.preciseSeekRequests.isEmpty }
    } _: {
      "Automatic seek was not requested"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    player.advanceTime(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    #expect(player.preciseSeekRequests.count == 1)
  }

  @Test("temporary selection wins over defaults without changing persisted preferences")
  func temporarySelection() async throws {
    let (episode, _) = try await prepared()
    let viewModel = PlayBarViewModel()
    let settings = Container.shared.userSettings()
    #expect(viewModel.silenceMode == .gentle)
    settings.$silenceMode.new(.balanced)
    #expect(viewModel.silenceMode == .balanced)
    viewModel.selectSilenceMode(.off)
    settings.$silenceMode.new(.aggressive)
    #expect(viewModel.silenceMode == .off)
    #expect(settings.silenceMode == .aggressive)
    #expect(
      try await Container.shared.repo().podcastEpisode(episode.id)?.podcast.silenceMode == nil
    )
    await Container.shared.playManager().pause()
    #expect(viewModel.silenceMode == .off)
  }

  @Test("automatic cuts exclude removed audio from heard coverage and leave Undo unchanged")
  func coverage() async throws {
    let (episode, player) = try await prepared(.init(start: 6, end: 18))
    let viewModel = PlayBarViewModel()
    await Container.shared.playManager().play()
    player.advanceTime(to: .seconds(6.5))
    try await Wait.until(maxAttempts: 200) {
      await MainActor.run { abs(player.currentTime().seconds - 17.7) < 0.001 }
    } _: {
      "Silence was not shortened"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    player.advanceTime(to: .seconds(21))
    try await Wait.until(maxAttempts: 200) {
      try await Container.shared.repo().episode(episode.id)?.currentTime == .seconds(21)
    } _: {
      "Playback progress was not saved"
    }
    let data = try #require(
      try await Container.shared.appDB().reader
        .read { db in
          try Data.fetchOne(
            db,
            sql: "SELECT playbackCoverage FROM episode WHERE id = ?",
            arguments: [episode.id]
          )
        }
    )
    let coverage = PlaybackCoverage(durationSeconds: 30, data: data)
    #expect(coverage.coveredSeconds < 18)
    #expect(coverage.coveredSeconds >= 9)
    #expect(viewModel.undoSeekDirection == nil)
  }

  @Test("silence metadata failure does not discard playable cached audio")
  func metadataFailure() async throws {
    let (episode, _) = try await prepared()
    let url = try #require(episode.episode.cachedURL)
    await Container.shared.playManager().stop()
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(sql: "DELETE FROM cachedAudioContent")
        try db.execute(
          sql: """
            CREATE TEMP TRIGGER fail_silence_metadata BEFORE INSERT ON cachedAudioContent
            BEGIN SELECT RAISE(ABORT, 'metadata unavailable'); END
            """
        )
      }
    try await Container.shared.playManager().load(episode)
    #expect(try await Container.shared.repo().episode(episode.id)?.cachedURL == url)
    #expect(Container.shared.podAVPlayer().playbackSnapshot().isFromCache)
  }

  @Test("a local map never cuts the remote stream and readiness preserves playback")
  func remoteReadiness() async throws {
    let episode = try await Create.podcastEpisode()
    let manager = Container.shared.playManager()
    try await manager.play(episode)
    try await PlayHelpers.waitFor(.playing)
    let player = Container.shared.avPlayer() as! FakeAVPlayer
    player.advanceTime(to: .seconds(2))
    await manager.setRate(1.5)
    let download = try await CacheHelpers.waitForDownloadTask(episode.id)
    try await CacheHelpers.simulateBackgroundFinish(download)
    let url = try await CacheHelpers.waitForCached(episode.id)
    let store = Container.shared.silenceStore()
    let content = try #require(try await store.content(for: url.lastPathComponent))
    try await store.publish(
      SilenceMap(duration: 30, intervals: [.init(start: 1, end: 10)]),
      for: content
    )
    let entered = ThreadSafe(false)
    let release = AsyncSemaphore(value: 0)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: url) { _ in
        entered(true)
        await release.wait()
        return (true, .seconds(30))
      }
    defer { release.signal() }
    PlayBarViewModel().selectSilenceMode(.gentle)
    try await Wait.until(maxAttempts: 200, { entered() }, { "Cached asset load did not start" })
    #expect(!Container.shared.podAVPlayer().playbackSnapshot().isFromCache)
    #expect(player.preciseSeekRequests.isEmpty)
    release.signal()
    try await Wait.until(maxAttempts: 200) { @MainActor in
      Container.shared.podAVPlayer().playbackSnapshot().isFromCache
        && !player.preciseSeekRequests.isEmpty
    } _: {
      "Ready local audio did not replace the remote source"
    }
    #expect(player.preciseSeekRequests.first?.0 == .seconds(2))
    #expect(Container.shared.sharedState().silenceOverride?.mode == .gentle)
    (player.current as! FakeAVPlayerItem).setStatus(.readyToPlay)
    player.advanceTime(to: .seconds(2))
    try await Wait.until(maxAttempts: 200) { @MainActor in
      player.preciseSeekRequests.count == 2
    } _: {
      "Local source did not activate silence shortening"
    }
    #expect(player.rate == 1.5)
    #expect(Container.shared.userSettings().silenceMode == .off)
  }

  @Test("media-services recovery preserves the same playback's temporary mode")
  func recovery() async throws {
    let (episode, player) = try await prepared()
    let viewModel = PlayBarViewModel()
    viewModel.selectSilenceMode(.aggressive)
    await Container.shared.playManager().setRate(1.8)
    Container.shared.sharedState().setStopAfterCurrentEpisode(true)
    Container.shared.notifier().continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await Wait.until(maxAttempts: 200) { @MainActor in
      (Container.shared.avPlayer() as! FakeAVPlayer) != player
    } _: {
      "Media services did not rebuild the player"
    }
    try await PlayHelpers.waitFor(.stopped)
    await Container.shared.playManager().play()
    try await PlayHelpers.waitFor(.playing)
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
    #expect(viewModel.silenceMode == .aggressive)
    #expect((Container.shared.avPlayer() as! FakeAVPlayer).rate == 1.8)
    #expect(Container.shared.sharedState().stopAfterCurrentEpisode)
    #expect(Container.shared.sharedState().silenceOverride?.episodeID == episode.id)
  }

  @Test("a failed position write after a cut cannot mark skipped audio as heard")
  func failedPositionWrite() async throws {
    let (episode, player) = try await prepared(.init(start: 6, end: 18))
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        try db.execute(
          sql: """
            CREATE TEMP TRIGGER fail_cut_position BEFORE UPDATE OF currentTime ON episode
            WHEN NEW.currentTime > 10 AND NEW.currentTime < 20
            BEGIN SELECT RAISE(ABORT, 'position unavailable'); END
            """
        )
      }
    await Container.shared.playManager().play()
    player.advanceTime(to: .seconds(6.5))
    try await Wait.until(maxAttempts: 200) { @MainActor in
      abs(player.currentTime().seconds - 17.7) < 0.001
    } _: {
      "Silence was not shortened"
    }
    try await PlayHelpers.waitForPeriodicTimeObserver()
    player.advanceTime(to: .seconds(21))
    try await Wait.until(maxAttempts: 200) {
      try await Container.shared.repo().episode(episode.id)?.currentTime == .seconds(21)
    } _: {
      "Later playback did not save its actual position"
    }
    let data = try #require(
      try await Container.shared.appDB().reader
        .read { db in
          try Data.fetchOne(
            db,
            sql: "SELECT playbackCoverage FROM episode WHERE id = ?",
            arguments: [episode.id]
          )
        }
    )
    #expect(PlaybackCoverage(durationSeconds: 30, data: data).coveredSeconds < 18)
  }
}
