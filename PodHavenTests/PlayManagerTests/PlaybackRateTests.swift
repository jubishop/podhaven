// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("Playback rate tests", .container)
@MainActor struct PlaybackRateTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    await PlayHelpers.setupCommandHandling()
  }

  // MARK: - Playback Rate

  @Test("setting rate while playing changes rate immediately")
  func settingRateWhilePlayingChangesRateImmediately() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    let newRate: Float = 1.5
    await playManager.setRate(newRate)

    #expect(avPlayer.rate == newRate)
    #expect(sharedState.playRate == newRate)
  }

  @Test("setting rate while waiting to play changes rate immediately")
  func settingRateWhileWaitingToPlayChangesRateImmediately() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    avPlayer.waitingToPlay()
    try await PlayHelpers.waitFor(.waiting)

    let newRate: Float = 2.0
    await playManager.setRate(newRate)

    #expect(avPlayer.rate == newRate)
    #expect(sharedState.playRate == newRate)
  }

  @Test("setting rate while paused only changes default rate")
  func settingRateWhilePausedOnlyChangesDefaultRate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)

    let newRate: Float = 1.75
    await playManager.setRate(newRate)

    // Rate should still be 0 when paused
    #expect(avPlayer.rate == 0.0)
    // But sharedState.playRate should be updated
    #expect(sharedState.playRate == newRate)

    // Verify defaultRate was changed by playing and checking the rate
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    #expect(avPlayer.rate == newRate)
  }

  @Test("sharedState playRate always updates regardless of playback status")
  func sharedStatePlayRateAlwaysUpdatesRegardlessOfPlaybackStatus() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    // Test when paused
    try await PlayHelpers.waitFor(.paused)
    let pausedRate: Float = 1.25
    await playManager.setRate(pausedRate)
    #expect(sharedState.playRate == pausedRate)

    // Test when playing
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    let playingRate: Float = 1.5
    await playManager.setRate(playingRate)
    #expect(sharedState.playRate == playingRate)

    // Test when paused again
    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)
    let pausedAgainRate: Float = 2.0
    await playManager.setRate(pausedAgainRate)
    #expect(sharedState.playRate == pausedAgainRate)
  }

  @Test("default playback rate set before initialization is used when playing")
  func defaultPlaybackRateSetBeforeInitializationIsUsedWhenPlaying() async throws {
    Log.setTestSystem()

    // Set default playback rate before starting playManager
    userSettings.$defaultPlaybackRate.withLock { $0 = 1.5 }

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Verify the rate matches the default we set
    #expect(avPlayer.rate == 1.5)
    #expect(sharedState.playRate == 1.5)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 1.5
    )
  }

  @Test("podcast with defaultPlaybackRate uses that rate when loaded and played")
  func podcastWithDefaultPlaybackRateUsesThatRateWhenLoadedAndPlayed() async throws {
    Log.setTestSystem()

    await playManager.start()

    // Create a podcast with a specific defaultPlaybackRate
    let customRate: Double = 1.75
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(defaultPlaybackRate: customRate),
        unsavedEpisode: try Create.unsavedEpisode()
      )
    )

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Verify both SharedState and AVPlayer use the podcast's defaultPlaybackRate
    #expect(sharedState.playRate == Float(customRate))
    #expect(avPlayer.rate == Float(customRate))
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: customRate
    )
  }

  @Test(
    "changing defaultPlaybackRate updates MPNowPlayingInfoPropertyDefaultPlaybackRate for new episodes"
  )
  func changingDefaultPlaybackRateUpdatesMPNowPlayingInfoPropertyDefaultPlaybackRateForNewEpisodes()
    async throws
  {
    await playManager.start()
    let (firstEpisode, secondEpisode, thirdEpisode) = try await Create.threePodcastEpisodes()

    // Load first episode with default rate of 1.0
    try await playManager.load(firstEpisode)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 1.0
    )

    // Change the default playback rate - current episode should keep its rate
    userSettings.$defaultPlaybackRate.withLock { $0 = 1.5 }

    // The currently loaded episode should NOT update (it has its own defaultPlaybackRate)
    // Verify it still has 1.0
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 1.0
    )

    // Load a new episode - it should use the updated default rate
    try await playManager.load(secondEpisode)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 1.5
    )

    // Change it again
    userSettings.$defaultPlaybackRate.withLock { $0 = 2.0 }

    // Current episode should still have 1.5
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 1.5
    )

    // Load another new episode - it should use the new default rate of 2.0
    try await playManager.load(thirdEpisode)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyDefaultPlaybackRate,
      value: 2.0
    )
  }
}
