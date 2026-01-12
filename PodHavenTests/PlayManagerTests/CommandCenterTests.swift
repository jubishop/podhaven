// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("Command center tests", .container)
@MainActor struct CommandCenterTests {
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
  }

  // MARK: - Media Services Reset

  @Test("media services reset notification restores to paused")
  func mediaServicesResetNotificationRestoresPlaybackState() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    // Load an episode
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.pause()
    let initialCallCount = await audioSession.configureCallCount
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await PlayHelpers.waitForLoadResponse(
      for: podcastEpisode.episode.mediaURL,
      count: initialLoadCount + 1
    )

    // Verify onDeck is restored properly
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Verify playback state is restored to paused
    try await PlayHelpers.waitFor(.paused)
  }

  @Test("media services reset notification with no episode does nothing")
  func mediaServicesResetNotificationWithNoEpisodeDoesNothing() async throws {
    await playManager.start()
    // Start with no episode loaded
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    // Call count goes up, podAVPlayer reset, but nothing else changes.
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)
  }

  // MARK: - Next Track Command

  @Test("nextTrackCommand is disabled when queue is empty")
  func nextTrackCommandIsDisabledWhenQueueIsEmpty() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    // Wait for queue observation to update command state
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to be disabled when queue is empty" }
    )
  }

  @Test("nextTrackCommand is enabled when queue has episodes")
  func nextTrackCommandIsEnabledWhenQueueHasEpisodes() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    // Wait for queue observation to update command state
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled when queue has episodes" }
    )
  }

  @Test("nextTrackCommand is disabled after queue becomes empty")
  func nextTrackCommandIsDisabledAfterQueueBecomesEmpty() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    // Wait for nextTrackCommand to be enabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled" }
    )

    // Remove episode from queue
    try await queue.dequeue(queuedEpisode.id)

    // Wait for nextTrackCommand to be disabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to be disabled after queue becomes empty" }
    )
  }

  @Test("nextTrackCommand advances to next episode when enabled")
  func nextTrackCommandAdvancesToNextEpisodeWhenEnabled() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()

    // Wait for nextTrackCommand to be enabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to be enabled" }
    )

    // Fire next track command
    mpRemoteCommandCenter.fireNextTrack()

    // Verify we advanced to the next episode
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(queuedEpisode.episode.mediaURL)
  }

  @Test("queue count updates MPNowPlayingInfoPropertyPlaybackQueueCount")
  func queueCountUpdatesMPNowPlayingInfoPropertyPlaybackQueueCount() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode1, queuedEpisode2) =
      try await Create.threePodcastEpisodes()

    try await playManager.load(playingEpisode)

    // Wait for queue count to be 1 (current item only)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Add first episode to queue
    try await queue.unshift(queuedEpisode1.id)

    // Wait for queue count to be 2 (current + 1 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Add second episode to queue
    try await queue.unshift(queuedEpisode2.id)

    // Wait for queue count to be 3 (current + 2 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 3
      },
      { @MainActor in
        """
        Expected queue count to be 3, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Remove first episode from queue
    try await queue.dequeue(queuedEpisode1.id)

    // Wait for queue count to be 2 (current + 1 queued)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2 after removal, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    // Remove second episode from queue
    try await queue.dequeue(queuedEpisode2.id)

    // Wait for queue count to be 1 (current item only)
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1 after all removed, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )
  }

  @Test("nextTrackCommand disables when queue empties while paused")
  func nextTrackCommandDisablesWhenQueueEmptiesWhilePaused() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (currentEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(currentEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Ensure initial state reflects both current and queued episodes
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 2
      },
      { @MainActor in
        """
        Expected queue count to be 2, got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrackCommand to start enabled" }
    )

    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)

    try await queue.dequeue(queuedEpisode.id)

    // Queue is empty but current episode remains paused
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to disable when queue becomes empty" }
    )
    try await Wait.until(
      { @MainActor in
        self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] as? Int == 1
      },
      { @MainActor in
        """
        Expected queue count to be 1 (current item only), got \
        \(String(describing: self.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount]))
        """
      }
    )

    await playManager.finishEpisode(currentEpisode.id)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrackCommand to stay disabled after finishing with empty queue" }
    )
    try await Wait.until(
      { @MainActor in self.nowPlayingInfo == nil },
      { @MainActor in "Expected nowPlayingInfo to clear after finishing episode" }
    )
  }

  // MARK: - Skip Interval Mode

  @Test("skipInterval mode does not set queue info in nowPlayingInfo")
  func skipIntervalModeDoesNotSetQueueInfoInNowPlayingInfo() async throws {
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    // Wait for nowPlayingInfo to be set
    try await Wait.until(
      { @MainActor in self.nowPlayingInfo != nil },
      { "Expected nowPlayingInfo to be set" }
    )

    // Verify queue properties are NOT set
    #expect(nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueIndex] == nil)
    #expect(nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] == nil)
  }

  @Test("skipInterval mode keeps next and previous track commands always enabled")
  func skipIntervalModeKeepsNextAndPreviousTrackCommandsAlwaysEnabled() async throws {
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    // Wait for commands to be registered
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrack to be enabled in skipInterval mode" }
    )
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == true },
      { "Expected previousTrack to be enabled in skipInterval mode" }
    )

    // Verify they stay enabled even with empty queue
    #expect(mpRemoteCommandCenter.nextTrack.isEnabled == true)
    #expect(mpRemoteCommandCenter.previousTrack.isEnabled == true)
  }

  @Test("skipInterval mode nextTrack command seeks forward 30 seconds")
  func skipIntervalModeNextTrackCommandSeeksForward30Seconds() async throws {
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Start at 60 seconds
    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    // Fire next track command
    mpRemoteCommandCenter.fireNextTrack()

    // Should seek forward 30 seconds
    let expectedTime = CMTime.seconds(90)
    try await PlayHelpers.waitFor(expectedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == expectedTime)

    // Episode should still be playing, not finished
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("skipInterval mode previousTrack command seeks backward 15 seconds")
  func skipIntervalModePreviousTrackCommandSeeksBackward15Seconds() async throws {
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Start at 60 seconds
    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    // Fire previous track command
    mpRemoteCommandCenter.firePreviousTrack()

    // Should seek backward 15 seconds
    let expectedTime = CMTime.seconds(45)
    try await PlayHelpers.waitFor(expectedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == expectedTime)

    // Episode should still be playing
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("skipInterval mode does not advance to next episode on nextTrack")
  func skipIntervalModeDoesNotAdvanceToNextEpisodeOnNextTrack() async throws {
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: playingEpisode.episode.mediaURL,
      data: (true, duration)
    )

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Start at 60 seconds
    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    // Fire next track command
    mpRemoteCommandCenter.fireNextTrack()

    // Should seek forward 30 seconds, not advance to next episode
    let expectedTime = CMTime.seconds(90)
    try await PlayHelpers.waitFor(expectedTime)

    // Verify we're still on the same episode
    try await PlayHelpers.waitForOnDeck(playingEpisode)
    try await PlayHelpers.waitForQueue([queuedEpisode])
  }

  @Test("changing nextTrackBehavior toggles remote command availability")
  func changingNextTrackBehaviorTogglesCommandAvailability() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    try await Wait.until(
      { @MainActor in self.sharedState.queueCount > 0 },
      { "Expected queue count to update after enqueuing episode" }
    )

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrack to be enabled in nextEpisode mode" }
    )
    #expect(mpRemoteCommandCenter.previousTrack.isEnabled == false)

    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }

    try await Wait.until(
      {
        @MainActor in
        self.mpRemoteCommandCenter.nextTrack.isEnabled == true
          && self.mpRemoteCommandCenter.previousTrack.isEnabled == true
      },
      { "Expected both next/previous track to be enabled in skipInterval mode" }
    )

    userSettings.$nextTrackBehavior.withLock { $0 = .nextEpisode }

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == false },
      { "Expected previousTrack to disable when returning to nextEpisode mode" }
    )
  }

  @Test("changing nextTrackBehavior switches command actions")
  func changingNextTrackBehaviorSwitchesCommandActions() async throws {
    Log.setTestSystem()

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    let duration = CMTime.seconds(300)
    await episodeAssetLoader.respond(
      to: playingEpisode.episode.mediaURL,
      data: (true, duration)
    )

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    try await Wait.until(
      { @MainActor in self.sharedState.queueCount > 0 },
      { "Expected queue count to reflect queued episode" }
    )

    // Switch to skip-interval behavior and verify we stay on the same episode when using next track.
    userSettings.$nextTrackBehavior.withLock { $0 = .skipInterval }
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackQueueIndex,
      value: nil
    )

    let startTime = CMTime.seconds(45)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.fireNextTrack()

    let expectedSkipTime = CMTime.seconds(75)
    try await PlayHelpers.waitFor(expectedSkipTime)
    try await PlayHelpers.waitForOnDeck(playingEpisode)
    #expect(PlayHelpers.nowPlayingCurrentTime == expectedSkipTime)

    // Switching back to next-episode should dequeue to the queued episode.
    userSettings.$nextTrackBehavior.withLock { $0 = .nextEpisode }
    mpRemoteCommandCenter.fireNextTrack()

    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitForQueue([])
  }

  // MARK: - Playback Rate

  @Test("changePlaybackRate command is enabled")
  func changePlaybackRateCommandIsEnabled() async throws {
    await playManager.start()

    #expect(mpRemoteCommandCenter.changePlaybackRate.isEnabled == true)
  }

  @Test("changePlaybackRate command has supported rates configured")
  func changePlaybackRateCommandHasSupportedRatesConfigured() async throws {
    await playManager.start()

    let supportedRates = mpRemoteCommandCenter.changePlaybackRate.supportedPlaybackRates
    #expect(supportedRates.count == 13)
    #expect(supportedRates.contains(0.8))
    #expect(supportedRates.contains(0.9))
    #expect(supportedRates.contains(1.0))
    #expect(supportedRates.contains(1.5))
    #expect(supportedRates.contains(2.0))
  }

  @Test("changePlaybackRate command changes playback rate")
  func changePlaybackRateCommandChangesPlaybackRate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Verify initial rate is 1.0 (default)
    #expect(sharedState.playRate == 1.0)

    // Fire command to change to 1.5x
    mpRemoteCommandCenter.fireChangePlaybackRate(1.5)

    // Wait for rate to update
    try await Wait.until(
      { Container.shared.sharedState().playRate == 1.5 },
      { "Expected playback rate to be 1.5, got \(Container.shared.sharedState().playRate)" }
    )

    // Fire command to change to 0.75x
    mpRemoteCommandCenter.fireChangePlaybackRate(0.75)

    // Wait for rate to update
    try await Wait.until(
      { Container.shared.sharedState().playRate == 0.75 },
      { "Expected playback rate to be 0.75, got \(Container.shared.sharedState().playRate)" }
    )
  }

  @Test("changePlaybackRate command updates AVPlayer rate")
  func changePlaybackRateCommandUpdatesAVPlayerRate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Fire command to change to 2.0x
    mpRemoteCommandCenter.fireChangePlaybackRate(2.0)

    // Wait for AVPlayer rate to update
    try await Wait.until(
      { await self.avPlayer.rate == 2.0 },
      { await "Expected AVPlayer rate to be 2.0, got \(self.avPlayer.rate)" }
    )
  }
}
