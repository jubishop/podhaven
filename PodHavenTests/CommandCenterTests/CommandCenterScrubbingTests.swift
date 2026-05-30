// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Command Center scrubbing tests", .container)
@MainActor struct CommandCenterScrubbingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test("scrubbing is enabled by default")
  func scrubbingEnabledByDefault() async throws {
    #expect(userSettings.commandCenterScrubbingEnabled == true)
    #expect(mpRemoteCommandCenter.changePlaybackPosition.isEnabled == true)
  }

  @Test("toggling the setting flips changePlaybackPosition availability")
  func togglingSettingFlipsChangePlaybackPosition() async throws {
    await playManager.start()

    userSettings.$commandCenterScrubbingEnabled.new(false)
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.changePlaybackPosition.isEnabled == false },
      { "Expected changePlaybackPosition to be disabled when scrubbing is off" }
    )

    userSettings.$commandCenterScrubbingEnabled.new(true)
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.changePlaybackPosition.isEnabled == true },
      { "Expected changePlaybackPosition to be re-enabled when scrubbing is on" }
    )
  }

  @Test("remote seek applies while scrubbing is enabled")
  func remoteSeekAppliesWhileEnabled() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(240))
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.fireSeek(to: 120)

    let expectedTime = CMTime.seconds(120)
    try await PlayHelpers.waitFor(expectedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == expectedTime)
  }

  @Test("remote seek is dropped while scrubbing is disabled")
  func remoteSeekDroppedWhileDisabled() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(240))
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    userSettings.$commandCenterScrubbingEnabled.new(false)
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.changePlaybackPosition.isEnabled == false },
      { "Expected changePlaybackPosition to be disabled when scrubbing is off" }
    )

    mpRemoteCommandCenter.fireSeek(to: 200)
    #expect(sharedState.onDeck?.currentTime == startTime)

    userSettings.$commandCenterScrubbingEnabled.new(true)
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.changePlaybackPosition.isEnabled == true },
      { "Expected changePlaybackPosition to be re-enabled when scrubbing is on" }
    )

    mpRemoteCommandCenter.fireSeek(to: 90)
    try await PlayHelpers.waitFor(CMTime.seconds(90))
  }
}
