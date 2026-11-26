// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of persisted episode restoration tests", .container)
@MainActor struct PersistedEpisodeRestorationTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeDataLoader) private var dataLoader
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
    PlayHelpers.setupCommandHandling()
  }

  @Test("activation failure preserves persisted episode and recovers on retry")
  func activationFailurePreservesPersistedEpisodeAndRecoversOnRetry() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    sharedState.currentEpisodeID = podcastEpisode.id

    audioSession.activationError {
      $0 = NSError(
        domain: NSOSStatusErrorDomain,
        code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      )
    }

    await playManager.start()

    try #require(sharedState.currentEpisodeID == podcastEpisode.id)
    #expect(sharedState.onDeck == nil)
    try await PlayHelpers.waitForQueue([])

    audioSession.activationError { $0 = nil }
    await playManager.play()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    try await PlayHelpers.waitForQueue([])
  }

  @Test("asset failure during persisted restore keeps the episode on deck and out of Up Next")
  func assetFailureDuringPersistedRestoreKeepsEpisodeOnDeckAndOutOfUpNext() async throws {
    dataLoader.setDefaultHandler { url in
      FakeDataLoader.create(url).pngData()!
    }
    let (podcastEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(image: URL.valid())
    )
    try await queue.unshift(queuedEpisode.id)
    sharedState.currentEpisodeID = podcastEpisode.id
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )

    await playManager.start()

    try await PlayHelpers.waitForLoadResponse(for: podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await Wait.until(
      { @MainActor in sharedState.onDeck?.artwork != nil },
      { @MainActor in "Expected the restored episode's artwork in the play bar" }
    )

    await episodeAssetLoader.clearCustomHandler(for: podcastEpisode.episode)
    await playManager.toggle()

    try await PlayHelpers.waitForLoadResponse(for: podcastEpisode.episode.mediaURL, count: 2)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitForQueue([queuedEpisode])
  }

  @Test("play during a failing persisted restore keeps the episode on deck and out of Up Next")
  func playDuringFailingPersistedRestoreKeepsEpisodeOnDeckAndOutOfUpNext() async throws {
    let (podcastEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()
    try await queue.unshift(queuedEpisode.id)
    sharedState.currentEpisodeID = podcastEpisode.id
    let assetStarted = AsyncSemaphore(value: 0)
    let failAsset = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: podcastEpisode.episode.mediaURL) { _ in
      assetStarted.signal()
      await failAsset.wait()
      throw TestError.assetLoadFailure(podcastEpisode)
    }
    let start = Task { await playManager.start() }
    defer { failAsset.signal() }
    await assetStarted.wait()

    await playManager.play()
    failAsset.signal()
    await start.value

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    try await PlayHelpers.waitForQueue([queuedEpisode])
  }

  @Test("retrying a failed persisted restore reloads it as a fresh restore")
  func retryingFailedPersistedRestoreReloadsItAsFreshRestore() async throws {
    let podcastRate: Double = 1.5
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(defaultPlaybackRate: podcastRate),
        unsavedEpisode: try Create.unsavedEpisode()
      )
    )
    sharedState.currentEpisodeID = podcastEpisode.id
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    await playManager.start()
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    await playManager.play()

    try await PlayHelpers.waitForLoadResponse(for: podcastEpisode.episode.mediaURL, count: 2)
    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected an alert after the retried restore failed" }
    )
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForQueue([])

    await episodeAssetLoader.clearCustomHandler(for: podcastEpisode.episode)
    await playManager.play()

    try await PlayHelpers.waitForLoadResponse(for: podcastEpisode.episode.mediaURL, count: 3)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForPlayRate(Float(podcastRate))
    #expect(avPlayer.rate == Float(podcastRate))
    try await PlayHelpers.waitForQueue([])
  }

  @Test("foreground restoration resumes a deferred play request")
  func foregroundRestorationResumesDeferredPlayRequest() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    sharedState.currentEpisodeID = podcastEpisode.id

    audioSession.activationError {
      $0 = NSError(
        domain: NSOSStatusErrorDomain,
        code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      )
    }

    await playManager.start()
    await playManager.play()?.value

    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    #expect(sharedState.onDeck == nil)

    audioSession.activationError { $0 = nil }
    await playManager.restorePersistedEpisodeForForeground()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    try await PlayHelpers.waitForQueue([])
  }

  @Test("foreground restoration does not retry a terminal play failure")
  func foregroundRestorationDoesNotRetryTerminalPlayFailure() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    await #expect(throws: (any Error).self) {
      try await playManager.play(podcastEpisode)
    }
    #expect(
      await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL) == 1
    )

    await episodeAssetLoader.clearCustomHandler(for: podcastEpisode.episode)
    await playManager.restorePersistedEpisodeForForeground()

    #expect(
      await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL) == 1
    )
    #expect(sharedState.onDeck == nil)
  }

  @Test("episode intent recovers its selected target after activation failure")
  func episodeIntentRecoversSelectedTargetAfterActivationFailure() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    audioSession.activationError {
      $0 = NSError(
        domain: NSOSStatusErrorDomain,
        code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      )
    }

    let result = try await PlayEpisodeIntent(episodeID: podcastEpisode.id.rawValue).perform()
    withExtendedLifetime(result) {}

    #expect(sharedState.currentEpisodeID == nil)
    #expect(sharedState.onDeck == nil)

    audioSession.activationError { $0 = nil }
    await playManager.restorePersistedEpisodeForForeground()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
  }

  @Test("episode intent recovers its selected target instead of the prior episode")
  func episodeIntentRecoversSelectedTargetInsteadOfPriorEpisode() async throws {
    let (priorEpisode, selectedEpisode) = try await Create.twoPodcastEpisodes()
    sharedState.currentEpisodeID = priorEpisode.id

    audioSession.activationError {
      $0 = NSError(
        domain: NSOSStatusErrorDomain,
        code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      )
    }

    let result = try await PlayEpisodeIntent(episodeID: selectedEpisode.id.rawValue).perform()
    withExtendedLifetime(result) {}

    #expect(sharedState.currentEpisodeID == priorEpisode.id)
    #expect(sharedState.onDeck == nil)
    try await PlayHelpers.waitForQueue([])

    audioSession.activationError { $0 = nil }
    await playManager.restorePersistedEpisodeForForeground()

    try await PlayHelpers.waitForOnDeck(selectedEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == selectedEpisode.id)
    try await PlayHelpers.waitForQueue([priorEpisode])
  }

  @Test("play pause intent rolls back widget status when activation is deferred")
  func playPauseIntentRollsBackWidgetStatusWhenActivationIsDeferred() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    let widgetState = Container.shared.widgetState()
    sharedState.currentEpisodeID = podcastEpisode.id
    widgetState.playbackStatus = .stopped

    audioSession.activationError {
      $0 = NSError(
        domain: NSOSStatusErrorDomain,
        code: AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      )
    }

    let result = try await PlayPauseIntent(playing: true).perform()
    withExtendedLifetime(result) {}

    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)
    #expect(widgetState.playbackStatus == .stopped)

    audioSession.activationError { $0 = nil }
    await playManager.restorePersistedEpisodeForForeground()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
  }
}
