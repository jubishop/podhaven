// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("Seeking tests", .container)
@MainActor struct SeekingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
  }

  // MARK: - Seeking

  @Test("seeking updates current time")
  func seekingUpdatesCurrentTime() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)

    let originalTime = CMTime.seconds(120)
    await playManager.seek(to: originalTime)
    try await PlayHelpers.waitFor(originalTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == originalTime)
    #expect(PlayHelpers.nowPlayingProgress == originalTime.seconds / duration.seconds)

    let skipAmount = Double(30)
    let skipTime = CMTimeAdd(originalTime, CMTime.seconds(skipAmount))
    await playManager.seekForward(skipAmount)
    try await PlayHelpers.waitFor(skipTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == skipTime)
    #expect(PlayHelpers.nowPlayingProgress == skipTime.seconds / duration.seconds)

    let rewindAmount = Double(15)
    let rewindTime = CMTimeSubtract(skipTime, CMTime.seconds(rewindAmount))
    await playManager.seekBackward(rewindAmount)
    try await PlayHelpers.waitFor(rewindTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == rewindTime)
    #expect(PlayHelpers.nowPlayingProgress == rewindTime.seconds / duration.seconds)
  }

  @Test("time update events are ignored while seeking")
  func timeUpdateEventsAreIgnoredWhileSeeking() async throws {
    await playManager.start()
    let (failedEpisode, successfulEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(failedEpisode)

    // After this failed seek, all time advancement is being ignored
    avPlayer.seekHandler = { _ in false }
    let failedSeekTime = CMTime.seconds(60)
    await playManager.seek(to: failedSeekTime)
    #expect(!PlayHelpers.hasPeriodicTimeObservation())

    await episodeAssetLoader.respond(
      to: successfulEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(120))
    )
    try await playManager.load(successfulEpisode)

    // While a seek is in progress, we will ignore time advancement until its success
    let seekSemaphore = AsyncSemaphore(value: 0)
    avPlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return true
    }
    let successfulSeekTime = CMTimeAdd(failedSeekTime, CMTime.seconds(30))
    await playManager.seek(to: successfulSeekTime)
    #expect(!PlayHelpers.hasPeriodicTimeObservation())

    // Our seek finishes successfully so time advancement observation is back
    seekSemaphore.signal()
    try await PlayHelpers.waitForPeriodicTimeObserver()
    let advancedTime = CMTimeAdd(successfulSeekTime, CMTime.seconds(10))
    avPlayer.advanceTime(to: advancedTime)  // Actually Triggers
    try await PlayHelpers.waitFor(advancedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == advancedTime)
  }

  @Test("seeking saves current time to database")
  func seekingSavesCurrentTimeToDatabase() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.seconds(240)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, duration)
    )
    try await playManager.load(podcastEpisode)

    var seekTime = CMTime.seconds(120)
    await playManager.seek(to: seekTime)
    try await PlayHelpers.waitFor(seekTime)
    try await PlayHelpers.waitForEpisode(
      podcastEpisode.id,
      attribute: \.currentTime,
      toBe: seekTime
    )

    seekTime = CMTime.seconds(60)
    await playManager.seek(to: seekTime)
    try await PlayHelpers.waitFor(seekTime)
    try await PlayHelpers.waitForEpisode(
      podcastEpisode.id,
      attribute: \.currentTime,
      toBe: seekTime
    )
  }
}
