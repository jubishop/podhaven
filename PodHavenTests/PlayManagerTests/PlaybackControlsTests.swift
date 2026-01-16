// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Semaphore
import Testing

@testable import PodHaven

@Suite("Playback controls tests", .container)
@MainActor struct PlaybackControlsTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    await PlayHelpers.setupCommandHandling()
  }

  // MARK: - Playback Controls

  @Test("play and pause functions play and pause playback")
  func playAndPauseFunctionsPlayAndPausePlayback() async throws {
    Log.setTestSystem()

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )
  }

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {
    Log.setTestSystem()

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    mpRemoteCommandCenter.firePlay()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    mpRemoteCommandCenter.firePause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    mpRemoteCommandCenter.fireTogglePlayPause()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    mpRemoteCommandCenter.fireTogglePlayPause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    mpRemoteCommandCenter.fireSkipForward(TimeInterval.seconds(2))
    try await PlayHelpers.waitFor(CMTime.seconds(2))

    mpRemoteCommandCenter.fireSkipBackward(TimeInterval.seconds(1))
    try await PlayHelpers.waitFor(CMTime.seconds(1))

    mpRemoteCommandCenter.fireSeek(to: TimeInterval.seconds(5))
    try await PlayHelpers.waitFor(CMTime.seconds(5))
  }

  @Test("seek commands are ignored during episode finish")
  func seekCommandsAreIgnoredDuringEpisodeFinish() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish episode which should start ignoring seek commands
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    mpRemoteCommandCenter.fireSeek(to: .seconds(5))
    try await PlayHelpers.waitFor(.zero)

    // Advance time to end the halt period
    await sleeper.advanceTime(by: .seconds(2))
    mpRemoteCommandCenter.fireSeek(to: .seconds(10))
    try await PlayHelpers.waitFor(.seconds(10))
  }

  @Test("audio session interruption stops and restarts playback")
  func audioSessionInterruptionStopsPlayback() async throws {
    Log.setTestSystem()

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let interruptionContinuation = notifier.continuation(
      for: AVAudioSession.interruptionNotification
    )

    // Interruption began: pause playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
      )
    )
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    // Interruption ended: resume playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
          AVAudioSessionInterruptionOptionKey:
            AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ]
      )
    )
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )
  }

  @Test("time update events update currentTime")
  func timeUpdateEventsUpdateCurrentTime() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let advancedTime = CMTime.seconds(10)
    avPlayer.advanceTime(to: advancedTime)
    try await PlayHelpers.waitFor(advancedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == advancedTime)
  }

  @Test("time updates throttle database writes to every 3 seconds")
  func timeUpdatesThrottleDatabaseWritesToEvery3Seconds() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    // Verify initial current time is 0
    let initialEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(initialEpisode?.currentTime == .zero)

    // Advance time by 1 second - should NOT write to DB yet
    avPlayer.advanceTime(to: .seconds(1))
    try await PlayHelpers.waitFor(.seconds(1))
    var updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .zero)

    // Advance time by 2 seconds total - should NOT write to DB yet
    avPlayer.advanceTime(to: .seconds(2))
    try await PlayHelpers.waitFor(.seconds(2))
    updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .zero)

    // Advance time by 3 seconds total - SHOULD write to DB now
    avPlayer.advanceTime(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    try await Wait.until(
      { try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime == .seconds(3) },
      { "Expected DB to be updated to 3 seconds" }
    )

    // Advance time by 4 seconds - should NOT write to DB yet (last write was at 3s)
    avPlayer.advanceTime(to: .seconds(4))
    try await PlayHelpers.waitFor(.seconds(4))
    updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .seconds(3))

    // Advance time by 6 seconds - SHOULD write to DB again (3s interval passed)
    avPlayer.advanceTime(to: .seconds(6))
    try await PlayHelpers.waitFor(.seconds(6))
    try await Wait.until(
      { try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime == .seconds(6) },
      { "Expected DB to be updated to 6 seconds" }
    )
  }

  @Test("waiting to play time control status updates playstate")
  func waitingToPlayTimeControlStatusUpdatesPlaystate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    avPlayer.waitingToPlay()
    try await PlayHelpers.waitFor(.waiting)
  }
}
