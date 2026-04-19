// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of NowPlayingInfo tests", .container)
@MainActor struct NowPlayingInfoTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  private var infoCenter: any MPNowPlayingInfoCenterable {
    Container.shared.mpNowPlayingInfoCenter()
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Periodic Elapsed Time Gate

  @Test("periodic time observer writes NowPlayingInfo elapsed every 3s of playback delta")
  func periodicObserverWritesElapsedEveryThreeSeconds() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(240))
    )
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    // Baseline: NowPlayingInfo elapsed is 0 after setOnDeck + play-driven
    // setPlaybackRate(1.0) chain (both write elapsed = onDeck.currentTime = 0).
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyElapsedPlaybackTime,
      value: 0.0
    )

    // Advance under the 3s gate — shared state advances but dict stays at 0.
    avPlayer.advanceTime(to: CMTime.seconds(1))
    try await PlayHelpers.waitFor(CMTime.seconds(1))
    #expect(PlayHelpers.nowPlayingCurrentTime == .zero)

    avPlayer.advanceTime(to: CMTime.seconds(2.9))
    try await PlayHelpers.waitFor(CMTime.seconds(2.9))
    #expect(PlayHelpers.nowPlayingCurrentTime == .zero)

    // Cross the gate — write fires.
    avPlayer.advanceTime(to: CMTime.seconds(3))
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyElapsedPlaybackTime,
      value: 3.0
    )

    // Next gate is 3s further: t=4 no write (still 3 in dict), t=6 write fires.
    avPlayer.advanceTime(to: CMTime.seconds(4))
    try await PlayHelpers.waitFor(CMTime.seconds(4))
    #expect(PlayHelpers.nowPlayingCurrentTime == CMTime.seconds(3))

    avPlayer.advanceTime(to: CMTime.seconds(6))
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyElapsedPlaybackTime,
      value: 6.0
    )
  }

  // MARK: - CurrentPlaybackDate

  @Test("setOnDeck writes CurrentPlaybackDate")
  func setOnDeckWritesCurrentPlaybackDate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let before = Date()
    try await playManager.load(podcastEpisode)
    let after = Date()

    let date =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentPlaybackDate] as? Date
    #expect(date != nil)
    if let date {
      #expect(date >= before)
      #expect(date <= after)
    }
  }

  @Test("periodic elapsed write refreshes CurrentPlaybackDate")
  func periodicElapsedWriteRefreshesCurrentPlaybackDate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(240))
    )
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let initialDate =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentPlaybackDate] as? Date
    #expect(initialDate != nil)

    // Cross the 3s gate so a periodic write fires.
    avPlayer.advanceTime(to: CMTime.seconds(3))
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyElapsedPlaybackTime,
      value: 3.0
    )

    let refreshedDate =
      infoCenter.nowPlayingInfo?[MPNowPlayingInfoPropertyCurrentPlaybackDate] as? Date
    #expect(refreshedDate != nil)
    if let initialDate, let refreshedDate {
      #expect(refreshedDate >= initialDate)
    }
  }

  // MARK: - playbackState Enum

  @Test("playbackState is paused after load")
  func playbackStateIsPausedAfterLoad() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)

    #expect(infoCenter.playbackState == .paused)
  }

  @Test("playbackState transitions .paused → .playing → .paused with play/pause")
  func playbackStateTransitionsWithPlayPause() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)

    try await PlayHelpers.play()
    try await Wait.until(
      { @MainActor in Container.shared.mpNowPlayingInfoCenter().playbackState == .playing },
      { @MainActor in
        """
        Expected playbackState to be .playing, got \
        \(Container.shared.mpNowPlayingInfoCenter().playbackState)
        """
      }
    )

    try await PlayHelpers.pause()
    try await Wait.until(
      { @MainActor in Container.shared.mpNowPlayingInfoCenter().playbackState == .paused },
      { @MainActor in
        """
        Expected playbackState to be .paused, got \
        \(Container.shared.mpNowPlayingInfoCenter().playbackState)
        """
      }
    )
  }

  @Test("clearOnDeck sets playbackState to stopped")
  func clearOnDeckSetsPlaybackStateToStopped() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)

    await playManager.clearOnDeck()

    #expect(infoCenter.playbackState == .stopped)
  }
}
