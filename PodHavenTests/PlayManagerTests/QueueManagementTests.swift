// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("Queue management tests", .container)
@MainActor struct QueueManagementTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
  }

  // MARK: - Queue Management

  @Test("loading an episode removes it from the queue")
  func loadingAnEpisodeRemovesItFromQueue() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await queue.unshift(playingEpisode.id)
    try await PlayHelpers.waitForQueue([playingEpisode, queuedEpisode])

    try await playManager.load(playingEpisode)

    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await PlayHelpers.waitForCurrentItem(playingEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(playingEpisode)
  }

  @Test("loading a new episode puts current episode back in queue")
  func loadingAnEpisodePutsCurrentEpisodeBackInQueue() async throws {
    await playManager.start()
    let (playingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(playingEpisode)
    try await playManager.load(incomingEpisode)

    try await PlayHelpers.waitForQueue([playingEpisode])
    try await PlayHelpers.waitForCurrentItem(incomingEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
  }

  @Test("loading failure unshifts onto queue")
  func loadingFailureUnshiftsOntoQueue() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    await #expect(throws: (any Error).self) {
      try await playManager.load(podcastEpisode)
    }

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([podcastEpisode])
    try await PlayHelpers.waitForNoCurrentItem()
  }

  @Test("loading failure with existing episode unshifts both onto queue")
  func loadingFailureWithExistingEpisodeUnshiftsBothOntoQueue() async throws {
    await playManager.start()
    let (playingEpisode, episodeToLoad) = try await Create.twoPodcastEpisodes()

    try await playManager.load(playingEpisode)
    await episodeAssetLoader.respond(
      to: episodeToLoad.episode.mediaURL,
      error: TestError.assetLoadFailure(playingEpisode)
    )
    await #expect(throws: (any Error).self) {
      try await playManager.load(episodeToLoad)
    }

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([episodeToLoad, playingEpisode])
    try await PlayHelpers.waitForNoCurrentItem()
  }

  @Test("loading same episode during load does not unshift onto queue")
  func loadingSameEpisodeDuringLoadDoesNotUnshiftOntoQueue() async throws {
    await playManager.start()
    let originalEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.executeMidLoad(for: originalEpisode.episode.mediaURL) {
      await episodeAssetLoader.clearCustomHandler(for: originalEpisode.episode)
      try await playManager.load(originalEpisode)
    }
    await #expect(throws: (any Error).self) {
      try await playManager.load(originalEpisode)
    }

    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForCurrentItem(originalEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(originalEpisode)
  }

  @Test("loading same episode during image fetching does not unshift onto queue")
  func loadingSameEpisodeDuringImageFetchingDoesNotUnshiftOntoQueue() async throws {
    await playManager.start()
    let originalEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.executeMidImageFetch(for: originalEpisode.image) {
      Container.shared.fakeDataLoader().clearCustomHandler(for: originalEpisode.image)
      try await playManager.load(originalEpisode)
    }
    try await playManager.load(originalEpisode)

    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForCurrentItem(originalEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(originalEpisode)
  }

  @Test("failed episode gets unshifted back to queue")
  func failedEpisodeGetsUnshiftedBackToQueue() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Now simulate the podcastEpisode failing after it becomes currentItem
    let currentItem = avPlayer.current as! FakeAVPlayerItem
    currentItem.setStatus(.failed)

    // The failed episode should be unshifted back to the front of the queue
    try await PlayHelpers.waitForNoCurrentItem()
    try await PlayHelpers.waitForQueue([podcastEpisode])
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitFor(.stopped)
  }
}
