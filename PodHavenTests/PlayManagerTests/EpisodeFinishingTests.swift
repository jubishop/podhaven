// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Episode finishing tests", .container)
@MainActor struct EpisodeFinishingTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
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

  @Test("newer load during markFinished survives stale finalization")
  func newerLoadDuringMarkFinishedSurvivesStaleFinalization() async throws {
    await playManager.start()
    let (currentEpisode, selectedEpisode) = try await Create.twoPodcastEpisodes()
    let fakeRepo = try #require(repo as? FakeRepo)

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    let markingStarted = AsyncSemaphore(value: 0)
    let finishMarking = AsyncSemaphore(value: 0)
    await fakeRepo.afterNextMarkFinished { episodeID in
      guard episodeID == currentEpisode.id else { return }
      markingStarted.signal()
      await finishMarking.wait()
    }

    let finalization = Task { await playManager.finishEpisode(currentEpisode.id) }
    defer {
      finalization.cancel()
      finishMarking.signal()
    }
    await markingStarted.wait()

    try await playManager.load(selectedEpisode)
    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)

    finishMarking.signal()
    await finalization.value

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
    #expect(try await queue.nextEpisode == nil)
  }

  @Test("finalization yields to a newer load already in preflight")
  func finalizationYieldsToNewerLoadAlreadyInPreflight() async throws {
    await playManager.start()
    let (currentEpisode, selectedEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    let configurationStarted = AsyncSemaphore(value: 0)
    let finishConfiguration = AsyncSemaphore(value: 0)
    Container.shared.configureAudioSession.context(.test) {
      {
        configurationStarted.signal()
        await finishConfiguration.wait()
        return true
      }
    }
    Container.shared.configureAudioSession.reset(.scope)

    let selectedPlay = Task { try await playManager.play(selectedEpisode) }
    defer {
      selectedPlay.cancel()
      finishConfiguration.signal()
    }
    await configurationStarted.wait()
    try await PlayHelpers.waitForOnDeck(currentEpisode)

    await playManager.finishEpisode(currentEpisode.id)
    finishConfiguration.signal()
    try await selectedPlay.value

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
    #expect(try await queue.nextEpisode == nil)
  }

  @Test("finalization during outgoing restoration leaves finished episode out of queue")
  func finalizationDuringOutgoingRestorationLeavesFinishedEpisodeOutOfQueue() async throws {
    await playManager.start()
    let (currentEpisode, selectedEpisode) = try await Create.twoPodcastEpisodes()
    let fakeQueue = try #require(queue as? FakeQueue)

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    let restorationStarted = AsyncSemaphore(value: 0)
    let finishRestoration = AsyncSemaphore(value: 0)
    fakeQueue.beforeUnshiftEpisode { episodeID in
      guard episodeID == currentEpisode.id else { return }
      restorationStarted.signal()
      await finishRestoration.wait()
    }

    let selectedPlay = Task { try await playManager.play(selectedEpisode) }
    defer {
      selectedPlay.cancel()
      finishRestoration.signal()
    }
    await restorationStarted.wait()
    #expect(sharedState.onDeck == nil)

    await playManager.finishEpisode(currentEpisode.id)
    finishRestoration.signal()
    try await selectedPlay.value

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
    #expect(try await queue.nextEpisode == nil)
  }

  @Test("stale finalization after a newer load removes the finished outgoing episode")
  func staleFinalizationAfterNewerLoadRemovesFinishedOutgoingEpisode() async throws {
    await playManager.start()
    let (currentEpisode, selectedEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()
    try await playManager.play(selectedEpisode)
    #expect(try await queue.nextEpisode?.id == currentEpisode.id)

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
    #expect(try await queue.nextEpisode == nil)
  }

  @Test("newer load during next episode resolution survives stale finalization")
  func newerLoadDuringNextEpisodeResolutionSurvivesStaleFinalization() async throws {
    await playManager.start()
    let (currentEpisode, queuedEpisode, selectedEpisode) =
      try await Create.threePodcastEpisodes()
    let fakeQueue = try #require(queue as? FakeQueue)

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    let resolutionStarted = AsyncSemaphore(value: 0)
    let finishResolution = AsyncSemaphore(value: 0)
    fakeQueue.beforeNextEpisode {
      resolutionStarted.signal()
      await finishResolution.wait()
    }

    let finalization = Task { await playManager.finishEpisode(currentEpisode.id) }
    defer {
      finalization.cancel()
      finishResolution.signal()
    }
    await resolutionStarted.wait()
    #expect(sharedState.onDeck == nil)

    try await playManager.load(selectedEpisode)
    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)

    finishResolution.signal()
    await finalization.value

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
  }

  @Test("newer play during automatic load cleanup survives stale autoplay")
  func newerPlayDuringAutomaticLoadCleanupSurvivesStaleAutoplay() async throws {
    await playManager.start()
    let (currentEpisode, automaticEpisode, selectedEpisode) =
      try await Create.threePodcastEpisodes()
    let fakeQueue = try #require(queue as? FakeQueue)

    try await queue.unshift(automaticEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    let automaticCleanupStarted = AsyncSemaphore(value: 0)
    let finishAutomaticCleanup = AsyncSemaphore(value: 0)
    fakeQueue.beforeNextDequeueEpisode { episodeID in
      #expect(episodeID == automaticEpisode.id)
      automaticCleanupStarted.signal()
      await finishAutomaticCleanup.wait()
    }

    let finalization = Task { await playManager.finishEpisode(currentEpisode.id) }
    defer {
      finalization.cancel()
      finishAutomaticCleanup.signal()
    }
    await automaticCleanupStarted.wait()
    try await PlayHelpers.waitForOnDeck(automaticEpisode)

    let selectedConfigurationStarted = AsyncSemaphore(value: 0)
    let finishSelectedConfiguration = AsyncSemaphore(value: 0)
    Container.shared.configureAudioSession.context(.test) {
      {
        selectedConfigurationStarted.signal()
        await finishSelectedConfiguration.wait()
        return true
      }
    }
    Container.shared.configureAudioSession.reset(.scope)

    let selectedPlay = Task { try await playManager.play(selectedEpisode) }
    defer {
      selectedPlay.cancel()
      finishSelectedConfiguration.signal()
    }
    await selectedConfigurationStarted.wait()

    finishAutomaticCleanup.signal()
    await finalization.value
    finishSelectedConfiguration.signal()
    try await selectedPlay.value

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitForCurrentItem(selectedEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("next episode preflight failure stops playback and preserves the queue")
  func nextEpisodePreflightFailureStopsPlaybackAndPreservesQueue() async throws {
    await playManager.start()
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(nextEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitForAudioActive(true)

    audioSession.configureError { $0 = TestError.simulatedFailure }
    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForAudioActive(false)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForNoCurrentItem()
    try await PlayHelpers.waitForQueue([nextEpisode])
  }

  @Test("next episode activation error stops playback and preserves the queue")
  func nextEpisodeActivationErrorStopsPlaybackAndPreservesQueue() async throws {
    await playManager.start()
    let (currentEpisode, nextEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(nextEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitForAudioActive(true)

    audioSession.activationError { $0 = TestError.simulatedFailure }
    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForAudioActive(false)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForNoCurrentItem()
    try await PlayHelpers.waitForQueue([nextEpisode])
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

  // MARK: - Stop After Current Episode

  @Test("stopAfterCurrentEpisode stops at episode end instead of advancing to queued episode")
  func stopAfterCurrentEpisodeStopsInsteadOfAdvancing() async throws {
    await playManager.start()
    let (currentEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    sharedState.setStopAfterCurrentEpisode(true)
    avPlayer.finishEpisode()

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(currentEpisode)
    try await PlayHelpers.waitForQueue([queuedEpisode])
    #expect(sharedState.stopAfterCurrentEpisode == false)
  }

  @Test("stopAfterCurrentEpisode stops instead of auto-playing top recommendation")
  func stopAfterCurrentEpisodeStopsInsteadOfRecommendation() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(true)
    let (currentEpisode, recommendedEpisode) = try await Create.twoPodcastEpisodes()

    sharedState.setRecommendedEpisodePool([recommendedEpisode.id])

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    sharedState.setStopAfterCurrentEpisode(true)
    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitForFinished(currentEpisode)
    #expect(sharedState.stopAfterCurrentEpisode == false)
  }

  @Test("manually starting a different episode clears stopAfterCurrentEpisode")
  func startingDifferentEpisodeClearsStopAfterCurrentEpisode() async throws {
    await playManager.start()
    let (currentEpisode, otherEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    sharedState.setStopAfterCurrentEpisode(true)
    try await playManager.load(otherEpisode)

    try await PlayHelpers.waitForOnDeck(otherEpisode)
    #expect(sharedState.stopAfterCurrentEpisode == false)
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

    sharedState.setRecommendedEpisodePool([recommendedEpisode.id])

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

    sharedState.setRecommendedEpisodePool([recommendedEpisode.id])

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

    sharedState.setRecommendedEpisodePool([])

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
    sharedState.setRecommendedEpisodePool([recommendedEpisode.id])

    try await playManager.load(currentEpisode)
    try await PlayHelpers.play()

    await playManager.finishEpisode(currentEpisode.id)

    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForCurrentItem(queuedEpisode.episode.mediaURL)
  }

  // Pins the cold-launch behavior: finishing the last episode with empty
  // queue and autoplay disabled clears `currentEpisodeID`, so a later cold
  // launch won't try to resume the finished episode.
  @Test("finishEpisode with no replacement nils currentEpisodeID")
  func finishEpisodeNoReplacementNilsCurrentEpisodeID() async throws {
    await playManager.start()
    userSettings.$autoPlayTopRecommendationWhenQueueEmpty.new(false)
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)

    await playManager.finishEpisode(podcastEpisode.id)

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForOnDeck(nil)
    #expect(sharedState.currentEpisodeID == nil)
  }

}
