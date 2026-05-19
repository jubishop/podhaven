// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Skip interval mode tests", .container)
@MainActor struct SkipIntervalModeTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Skip Interval Mode

  @Test("skipInterval mode does not set queue info in nowPlayingInfo")
  func skipIntervalModeDoesNotSetQueueInfoInNowPlayingInfo() async throws {
    userSettings.$nextTrackBehavior.new(.skipInterval)

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

  @Test("skipInterval mode enables next and previous track commands with OnDeck")
  func skipIntervalModeEnablesNextAndPreviousTrackCommandsWithOnDeck() async throws {
    userSettings.$nextTrackBehavior.new(.skipInterval)

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
    userSettings.$nextTrackBehavior.new(.skipInterval)

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
    userSettings.$nextTrackBehavior.new(.skipInterval)

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
    userSettings.$nextTrackBehavior.new(.skipInterval)

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

  // MARK: - Behavior Switching

  @Test("changing nextTrackBehavior toggles remote command availability")
  func changingNextTrackBehaviorTogglesCommandAvailability() async throws {

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
    #expect(mpRemoteCommandCenter.previousTrack.isEnabled == true)

    userSettings.$nextTrackBehavior.new(.skipInterval)

    try await Wait.until(
      {
        @MainActor in
        self.mpRemoteCommandCenter.nextTrack.isEnabled == true
          && self.mpRemoteCommandCenter.previousTrack.isEnabled == true
      },
      { "Expected both next/previous track to be enabled in skipInterval mode" }
    )

    userSettings.$nextTrackBehavior.new(.nextEpisode)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == true },
      { "Expected previousTrack to remain enabled in nextEpisode mode" }
    )
  }

  @Test("changing nextTrackBehavior switches command actions")
  func changingNextTrackBehaviorSwitchesCommandActions() async throws {

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
    userSettings.$nextTrackBehavior.new(.skipInterval)
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
    userSettings.$nextTrackBehavior.new(.nextEpisode)
    mpRemoteCommandCenter.fireNextTrack()

    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitForQueue([])
  }
}
