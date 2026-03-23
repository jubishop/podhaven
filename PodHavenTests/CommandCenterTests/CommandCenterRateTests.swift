// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Command center rate tests", .container)
@MainActor struct CommandCenterRateTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
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
