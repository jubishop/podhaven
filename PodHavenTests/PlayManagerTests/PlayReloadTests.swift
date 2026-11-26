// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Play reload tests", .container)
@MainActor struct PlayReloadTests {
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private let duration = CMTime.seconds(240)
  private let savedTime = CMTime.seconds(100)

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

  enum Reload: CaseIterable {
    case failedRestoreRecovery, mediaServicesResetRecovery, deferredRestore
  }

  enum Command: CaseIterable {
    case pause, togglePlayPause
  }

  @Test(
    "a remote pause or toggle during Play's reload leaves the episode paused",
    arguments: Reload.allCases,
    Command.allCases
  )
  func remoteCommandDuringReloadLeavesEpisodePaused(reload: Reload, command: Command)
    async throws
  {
    let podcastEpisode = try await awaitReload(reload)
    let playCount = avPlayer.playCallCount
    let assetStarted = AsyncSemaphore(value: 0)
    let finishAsset = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: podcastEpisode.episode.mediaURL) { [duration] _ in
      assetStarted.signal()
      await finishAsset.wait()
      return (true, duration)
    }
    defer { finishAsset.signal() }

    try await interruptPlayReload(with: command, once: assetStarted)
    finishAsset.signal()

    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == playCount)
  }

  @Test(
    "a remote pause or toggle during Play's failing reload keeps the episode On Deck",
    arguments: Reload.allCases,
    Command.allCases
  )
  func remoteCommandDuringFailingReloadKeepsEpisodeOnDeck(reload: Reload, command: Command)
    async throws
  {
    let podcastEpisode = try await awaitReload(reload)
    let mediaURL = podcastEpisode.episode.mediaURL
    let assetStarted = AsyncSemaphore(value: 0)
    let failAsset = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: mediaURL) { _ in
      assetStarted.signal()
      await failAsset.wait()
      throw TestError.assetLoadFailure(podcastEpisode)
    }
    defer { failAsset.signal() }

    try await interruptPlayReload(with: command, once: assetStarted)
    failAsset.signal()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForQueue([])

    await episodeAssetLoader.respond(to: mediaURL, data: (true, duration))
    mpRemoteCommandCenter.firePlay()
    try await PlayHelpers.waitForCurrentItem(mediaURL)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test(
    "a second play during a recovery reload's audio-session setup joins the reload",
    arguments: [OnDeckRecoveryState.Cause.failedRestore, .mediaServicesReset]
  )
  func secondPlayDuringRecoveryReloadJoinsIt(cause: OnDeckRecoveryState.Cause) async throws {
    let podcastEpisode = try await PlayHelpers.awaitOnDeckRecoveryReload(
      cause,
      duration: duration,
      currentTime: savedTime
    )
    let mediaURL = podcastEpisode.episode.mediaURL
    let loadCount = await episodeAssetLoader.responseCount(for: mediaURL)
    PlayHelpers.failAudioSessionConfiguration()
    mpRemoteCommandCenter.firePlay()
    try await PlayHelpers.waitForFailedAudioSessionConfigurationAttempt()
    let playRevision = playManager.playbackRequestRevision

    await playManager.play()

    #expect(playManager.playbackRequestRevision == playRevision)
    try await PlayHelpers.recoverAudioSessionConfiguration()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    #expect(await episodeAssetLoader.responseCount(for: mediaURL) == loadCount + 1)
  }

  @Test(
    "the widget play intent returns once Play's reload starts playback",
    arguments: Reload.allCases
  )
  func widgetPlayIntentReturnsOnceReloadPlays(reload: Reload) async throws {
    let podcastEpisode = try await awaitReload(reload)

    let result = try await PlayPauseIntent(playing: true).perform()
    withExtendedLifetime(result) {}

    #expect(sharedState.onDeck?.id == podcastEpisode.id)
    #expect(avPlayer.timeControlStatus == .playing)
    try await PlayHelpers.waitFor(.playing)
  }

  // MARK: - Helpers

  private func interruptPlayReload(with command: Command, once assetStarted: AsyncSemaphore)
    async throws
  {
    mpRemoteCommandCenter.firePlay()
    await assetStarted.wait()
    let playRevision = playManager.playbackRequestRevision
    switch command {
    case .pause: mpRemoteCommandCenter.firePause()
    case .togglePlayPause: mpRemoteCommandCenter.fireTogglePlayPause()
    }
    try await Wait.until(
      { await playManager.playbackRequestRevision != playRevision },
      { "Expected the remote \(command) to run while the reload is suspended" }
    )
  }

  private func awaitReload(_ reload: Reload) async throws -> PodcastEpisode {
    switch reload {
    case .failedRestoreRecovery:
      return try await PlayHelpers.awaitOnDeckRecoveryReload(
        .failedRestore,
        duration: duration,
        currentTime: savedTime
      )
    case .mediaServicesResetRecovery:
      return try await PlayHelpers.awaitOnDeckRecoveryReload(
        .mediaServicesReset,
        duration: duration,
        currentTime: savedTime
      )
    case .deferredRestore:
      let podcastEpisode = try await Create.podcastEpisode()
      sharedState.currentEpisodeID = podcastEpisode.id
      audioSession.activationError {
        $0 = NSError(
          domain: NSOSStatusErrorDomain,
          code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
        )
      }
      await playManager.start()
      try #require(sharedState.onDeck == nil)
      audioSession.activationError { $0 = nil }
      return podcastEpisode
    }
  }
}
