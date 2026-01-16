// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("Cache functionality tests", .container)
@MainActor struct CacheTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    await PlayHelpers.setupCommandHandling()
  }

  // MARK: - Cache Functionality

  @Test("loading episode with cached media uses cached URL")
  func loadingEpisodeWithCachedMediaUsesCachedURL() async throws {
    await playManager.start()
    let cachedFilename = "cached-episode.mp3"
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: cachedFilename)
    )

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.cachedURL!)

    // Verify the asset was loaded with the resolved cached URL
    let currentItem = avPlayer.current! as! FakeAVPlayerItem
    #expect(currentItem.url == podcastEpisode.episode.cachedURL!.rawValue)
  }

  @Test("loading episode without cached media uses original URL")
  func loadingEpisodeWithoutCachedMediaUsesOriginalURL() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)

    // Verify the asset was loaded with the original media URL
    let currentItem = avPlayer.current! as! FakeAVPlayerItem
    #expect(currentItem.url == podcastEpisode.episode.mediaURL.rawValue)
  }

  @Test("loading episode falls back to original URL if cached media URL fails")
  func loadingEpisodeFallsBackToOriginalURLIfCachedMediaURLFails() async throws {
    await playManager.start()
    let cachedFilename = "cached-episode.mp3"
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(cachedFilename: cachedFilename)
    )

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.cachedURL!,
      error: TestError.assetLoadFailure(podcastEpisode)
    )

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)

    // Verify the asset was loaded with the original media URL
    let currentItem = avPlayer.current! as! FakeAVPlayerItem
    #expect(currentItem.url == podcastEpisode.episode.mediaURL.rawValue)
  }

  @Test("episode cache is not cleared when loading")
  func episodeCacheIsNotClearedWhenLoading() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForQueue([])

    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }

  // MARK: - Swap to Cached

  @Test("pausing swaps from remote URL to cached URL")
  func pausingSwapsFromRemoteURLToCachedURL() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    // Load and play from remote URL
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.play()

    // Simulate cache completion
    let taskID = try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    // Pause should trigger swap to cached
    try await PlayHelpers.pause()
    try await PlayHelpers.waitForCurrentItem(cachedURL)
  }

  @Test("seeking swaps from remote URL to cached URL")
  func seekingSwapsFromRemoteURLToCachedURL() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    // Load and play from remote URL
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.play()

    // Simulate cache completion
    let taskID = try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    // Seek should trigger swap to cached
    await playManager.seek(to: .seconds(30))
    try await PlayHelpers.waitForCurrentItem(cachedURL)
  }

  @Test("waiting to play swaps from remote URL to cached URL")
  func waitingToPlaySwapsFromRemoteURLToCachedURL() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    // Load and play from remote URL
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.play()

    // Simulate cache completion
    let taskID = try await CacheHelpers.waitForDownloadTaskID(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    let cachedURL = try await CacheHelpers.waitForCached(podcastEpisode.id)

    // Waiting to play (buffering) should trigger swap to cached
    avPlayer.waitingToPlay()
    try await PlayHelpers.waitForCurrentItem(cachedURL)
  }
}
