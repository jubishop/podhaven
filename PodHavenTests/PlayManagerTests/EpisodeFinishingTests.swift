// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Episode finishing tests", .container)
@MainActor struct EpisodeFinishingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Episode Finishing

  @Test("finishing last episode with nothing queued clears state")
  func finishingLastEpisodeWithNothingQueuedClearsState() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    avPlayer.finishEpisode()

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForNoCurrentItem()
    #expect(sharedState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("finishing last episode will load next episode")
  func finishingLastEpisodeWillLoadNextEpisode() async throws {
    await playManager.start()
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(originalEpisode)

    // Once episode is finished it will try to load the queued episode
    try await PlayHelpers.play()
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForCurrentItem(queuedEpisode.episode.mediaURL)
  }

  @Test("advancing to next episode updates state")
  func advancingToNextEpisodeUpdatesState() async throws {
    await playManager.start()
    let (originalEpisode, queuedEpisode, incomingEpisode) =
      try await Create.threePodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await queue.unshift(incomingEpisode.id)

    try await playManager.load(originalEpisode)
    try await PlayHelpers.play()
    avPlayer.finishEpisode()

    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await PlayHelpers.waitForCurrentItem(incomingEpisode.episode.mediaURL)
  }

  @Test("advancing to mid-progress episode seeks to new time")
  func advancingToMidProgressEpisodeSeeksToNewTime() async throws {
    await playManager.start()
    let originalTime = CMTime.seconds(5)
    let queuedTime = CMTime.seconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime),
      Create.unsavedEpisode(currentTime: queuedTime)
    )

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(originalEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitFor(originalTime)

    avPlayer.finishEpisode()
    try await PlayHelpers.waitFor(queuedTime)
  }

  @Test("advancing to unplayed episode sets time to zero")
  func advancingToUnplayedEpisodeSetsTimeToZero() async throws {
    await playManager.start()
    let originalTime = CMTime.seconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime)
    )

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(originalEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitFor(originalTime)

    avPlayer.finishEpisode()
    try await PlayHelpers.waitFor(.zero)
  }

  @Test("episode is marked finished after playing to end")
  func episodeIsMarkedFinishedAfterPlayingToEnd() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForFinished(podcastEpisode)
  }

  @Test("finishEpisode clears onDeck and marks episode finished")
  func finishEpisodeClearsOnDeckAndMarksEpisodeFinished() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    await playManager.finishEpisode(podcastEpisode.id)

    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(podcastEpisode)
  }

  @Test("finishEpisode loads next episode if one exists")
  func finishEpisodeLoadsNextEpisodeIfOneExists() async throws {
    await playManager.start()
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(nextEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitForOnDeck(nextEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(nextEpisode.episode.mediaURL)
    try await PlayHelpers.waitForFinished(currentEpisode)
  }

  @Test("finishEpisode stops playback if no next episode exists")
  func finishEpisodeStopsPlaybackIfNoNextEpisodeExists() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitFor(.playing)

    await playManager.finishEpisode(podcastEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(podcastEpisode)
  }

  // MARK: - Auto-play Top Recommendation

  @Test(
    """
    finishEpisode auto-plays top recommendation when queue is empty and \
    autoPlayTopRecommendationWhenQueueEmpty is enabled
    """
  )
  func finishEpisodeAutoPlaysTopRecommendationWhenEnabled() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(true)
    let (currentEpisode, recommendedEpisode) = try await Create.twoPodcastEpisodes()

    sharedState.setTopRecommendations([recommendedEpisode.id])

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitForOnDeck(recommendedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(recommendedEpisode.episode.mediaURL)
    try await PlayHelpers.waitForFinished(currentEpisode)
  }

  @Test(
    """
    finishEpisode stops when autoPlayTopRecommendationWhenQueueEmpty is disabled, \
    even if recommendations are available
    """
  )
  func finishEpisodeStopsWhenAutoPlayDisabled() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(false)
    let (currentEpisode, recommendedEpisode) = try await Create.twoPodcastEpisodes()

    sharedState.setTopRecommendations([recommendedEpisode.id])

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(currentEpisode)
  }

  @Test("finishEpisode stops when auto-play is enabled but no recommendations are published")
  func finishEpisodeStopsWhenNoRecommendationsAvailable() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(true)
    let podcastEpisode = try await Create.podcastEpisode()

    sharedState.setTopRecommendations([])

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(podcastEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(podcastEpisode)
  }

  @Test("finishEpisode prefers queued episode over top recommendation")
  func finishEpisodeQueueTakesPrecedenceOverRecommendation() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(true)
    let (currentEpisode, queuedEpisode, recommendedEpisode) =
      try await Create.threePodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    sharedState.setTopRecommendations([recommendedEpisode.id])

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(queuedEpisode.episode.mediaURL)
  }

}
