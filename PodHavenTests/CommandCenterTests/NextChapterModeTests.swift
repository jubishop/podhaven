// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of Next chapter mode tests", .container)
@MainActor struct NextChapterModeTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
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

  // MARK: - Next Chapter Mode

  @Test("nextChapter mode keeps next and previous track always enabled")
  func nextChapterModeKeepsNextAndPreviousTrackAlwaysEnabled() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrack to be enabled in nextChapter mode" }
    )
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == true },
      { "Expected previousTrack to be enabled in nextChapter mode" }
    )
  }

  @Test("nextChapter mode does not set queue info in nowPlayingInfo")
  func nextChapterModeDoesNotSetQueueInfoInNowPlayingInfo() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)

    try await Wait.until(
      { @MainActor in self.nowPlayingInfo != nil },
      { "Expected nowPlayingInfo to be set" }
    )

    #expect(nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueIndex] == nil)
    #expect(nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackQueueCount] == nil)
  }

  @Test("nextChapter mode nextTrack navigates to next chapter")
  func nextChapterModeNextTrackNavigatesToNextChapter() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(
        duration: .seconds(3600),
        description: """
          5:00 Topic One
          15:00 Topic Two
          30:00 Topic Three
          """
      )
    )

    let duration = CMTime.seconds(3600)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Position at 6:00 (between 5:00 and 15:00 chapters)
    let startTime = CMTime.seconds(360)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.fireNextTrack()

    // Should navigate to 15:00
    let expectedTime = CMTime.seconds(900)
    try await PlayHelpers.waitFor(expectedTime)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("nextChapter mode previousTrack navigates to previous chapter")
  func nextChapterModePreviousTrackNavigatesToPreviousChapter() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(
        duration: .seconds(3600),
        description: """
          5:00 Topic One
          15:00 Topic Two
          30:00 Topic Three
          """
      )
    )

    let duration = CMTime.seconds(3600)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Position at 16:00 (between 15:00 and 30:00)
    let startTime = CMTime.seconds(960)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.firePreviousTrack()

    // Should navigate to 15:00
    let expectedTime = CMTime.seconds(900)
    try await PlayHelpers.waitFor(expectedTime)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("nextChapter mode previousTrack within 2s of chapter goes to prior chapter")
  func nextChapterModePreviousTrackWithin2SecondsGoesToPriorChapter() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(
        duration: .seconds(3600),
        description: """
          5:00 Topic One
          15:00 Topic Two
          30:00 Topic Three
          """
      )
    )

    let duration = CMTime.seconds(3600)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Position at 15:01 (within 2s of 15:00 chapter)
    let startTime = CMTime.seconds(901)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.firePreviousTrack()

    // Should skip past 15:00 and go to 5:00
    let expectedTime = CMTime.seconds(300)
    try await PlayHelpers.waitFor(expectedTime)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("nextChapter mode previousTrack before first chapter seeks to zero")
  func nextChapterModePreviousTrackBeforeFirstChapterSeeksToZero() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(
        duration: .seconds(3600),
        description: """
          5:00 Topic One
          15:00 Topic Two
          30:00 Topic Three
          """
      )
    )

    let duration = CMTime.seconds(3600)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Position at 3:00 (before first chapter at 5:00)
    let startTime = CMTime.seconds(180)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.firePreviousTrack()

    // Should seek to start
    try await PlayHelpers.waitFor(.zero)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("nextChapter mode nextTrack past last chapter finishes episode")
  func nextChapterModeNextTrackPastLastChapterFinishesEpisode() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      try Create.unsavedEpisode(
        duration: .seconds(3600),
        description: """
          5:00 Topic One
          15:00 Topic Two
          30:00 Topic Three
          """
      )
    )

    let duration = CMTime.seconds(3600)
    await episodeAssetLoader.respond(
      to: playingEpisode.episode.mediaURL,
      data: (true, duration)
    )

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Position at 35:00 (past last chapter at 30:00)
    let startTime = CMTime.seconds(2100)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.fireNextTrack()

    // Should advance to the queued episode
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("nextChapter mode nextTrack falls back to seekForward without chapters")
  func nextChapterModeNextTrackFallsBackToSeekForwardWithoutChapters() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

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

    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.fireNextTrack()

    // Should seek forward by default interval (30s)
    let expectedTime = CMTime.seconds(90)
    try await PlayHelpers.waitFor(expectedTime)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("nextChapter mode previousTrack falls back to seekBackward without chapters")
  func nextChapterModePreviousTrackFallsBackToSeekBackwardWithoutChapters() async throws {
    userSettings.$nextTrackBehavior.new(.nextChapter)

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

    let startTime = CMTime.seconds(60)
    await playManager.seek(to: startTime)
    try await PlayHelpers.waitFor(startTime)

    mpRemoteCommandCenter.firePreviousTrack()

    // Should seek backward by default interval (15s)
    let expectedTime = CMTime.seconds(45)
    try await PlayHelpers.waitFor(expectedTime)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
  }

  @Test("changing to nextChapter mode updates command availability")
  func changingToNextChapterModeUpdatesCommandAvailability() async throws {
    userSettings.$nextTrackBehavior.new(.nextEpisode)

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    // In nextEpisode mode with empty queue, nextTrack should be disabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == false },
      { "Expected nextTrack to be disabled in nextEpisode mode with empty queue" }
    )

    // Switch to nextChapter mode
    userSettings.$nextTrackBehavior.new(.nextChapter)

    // nextTrack should now be enabled
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.nextTrack.isEnabled == true },
      { "Expected nextTrack to be enabled in nextChapter mode" }
    )
    try await Wait.until(
      { @MainActor in self.mpRemoteCommandCenter.previousTrack.isEnabled == true },
      { "Expected previousTrack to be enabled in nextChapter mode" }
    )
  }
}
