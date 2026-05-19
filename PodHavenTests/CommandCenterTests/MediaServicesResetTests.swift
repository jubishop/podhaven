// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Media services reset tests", .container)
@MainActor struct MediaServicesResetTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.notifier) private var notifier
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
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Media Services Reset

  @Test("media services reset notification restores to paused")
  func mediaServicesResetNotificationRestoresPlaybackState() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    // Load an episode
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.pause()
    let initialCallCount = await audioSession.configureCallCount
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await PlayHelpers.waitForConfigureCallCount(atLeast: initialCallCount + 2)
    try await PlayHelpers.waitForLoadResponse(
      for: podcastEpisode.episode.mediaURL,
      count: initialLoadCount + 1
    )

    // Verify onDeck is restored properly
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Verify playback state is restored to paused
    try await PlayHelpers.waitFor(.paused)
  }

  @Test("media services reset notification with no episode does nothing")
  func mediaServicesResetNotificationWithNoEpisodeDoesNothing() async throws {
    await playManager.start()
    // Start with no episode loaded
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    // Call count goes up, podAVPlayer reset, but nothing else changes.
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)
  }

  @Test("media services reset with failing audio session stops gracefully")
  func mediaServicesResetWithFailingAudioSessionStopsGracefully() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.pause()

    audioSession.configureError { $0 = TestError.simulatedFailure }

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    try await PlayHelpers.waitFor(.stopped)
    try await Wait.until(
      { @MainActor in sharedState.onDeck == nil },
      { @MainActor in "Expected onDeck to clear after failed media services reset recovery" }
    )
    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected alert after failed audio session reconfiguration" }
    )
  }

  @Test("media services reset with no on-deck but queued episode loads top of queue")
  func mediaServicesResetWithNoOnDeckLoadsTopOfQueue() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let initialCallCount = await audioSession.configureCallCount

    // Put the episode in the queue but don't load it on deck
    try await queue.unshift(podcastEpisode.id)
    #expect(sharedState.onDeck == nil)

    // Trigger media services reset
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await PlayHelpers.waitForConfigureCallCount(atLeast: initialCallCount + 2)

    // The episode from the top of the queue should now be loaded on deck
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
  }
}
