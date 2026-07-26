// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
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

  // MARK: - Media Services Reset

  @Test("media services reset returns OnDeck to Up Next and waits for user")
  func mediaServicesResetReturnsOnDeckToUpNextAndWaitsForUser() async throws {
    try await LogCapture.withSink { sink in
      PlayHelpers.setupCommandHandling()
      await playManager.start()
      let resumeTime = CMTime.seconds(123)
      let (podcastEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
        Create.unsavedEpisode(currentTime: resumeTime)
      )

      try await queue.unshift(queuedEpisode.id)
      try await PlayHelpers.load(podcastEpisode)
      try await PlayHelpers.waitFor(resumeTime)
      try await PlayHelpers.pause()
      let initialAVPlayer = avPlayer
      initialAVPlayer.timeObservers.removeAll()
      initialAVPlayer.advanceTime(to: .zero)
      let initialConfigureCallCount = await audioSession.configureCallCount
      let initialLoadCount = await episodeAssetLoader.responseCount(
        for: podcastEpisode.episode.mediaURL
      )
      let initialActivationCount = await audioSession.activeCalls.filter(\.self).count

      notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await PlayHelpers.waitForConfigureCallCount(
        callCount: initialConfigureCallCount + 1
      )
      try await Wait.until(
        { await avPlayer != initialAVPlayer },
        { "Expected new AVPlayer to be created" }
      )
      try await PlayHelpers.waitForOnDeck(nil)
      try await PlayHelpers.waitFor(.stopped)
      try await PlayHelpers.waitForQueue([podcastEpisode, queuedEpisode])
      try await Wait.until(
        { @MainActor in alert.config?.title == "Audio Services Restarted" },
        { @MainActor in "Expected an audio-services reset explanation" }
      )

      #expect(
        await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
          == initialLoadCount
      )
      #expect(await audioSession.activeCalls.filter(\.self).count == initialActivationCount)
      let preservedEpisode = try #require(try await repo.podcastEpisode(podcastEpisode.id))
      #expect(preservedEpisode.currentTime == resumeTime)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
            }
        },
        { "Expected media-services reset telemetry" }
      )
      let telemetry = sink.captured()
        .filter {
          $0.level == .warning
            && $0.message.contains("event=mediaServicesResetHandled")
            && $0.message.contains("outcome=awaitingUserAction")
            && $0.message.contains("resumeEpisodeID=\(podcastEpisode.id)")
        }
      #expect(telemetry.count == 1)

      try await PlayHelpers.load(preservedEpisode)
      try await PlayHelpers.waitFor(.paused)
      try await PlayHelpers.waitFor(resumeTime)
      try await PlayHelpers.waitForQueue([queuedEpisode])
      try await Wait.until(
        { await audioSession.activeCalls.filter(\.self).count == initialActivationCount + 1 },
        { "Expected user-initiated load to reactivate the audio session" }
      )
    }
  }

  @Test("media services reset rebuilds without prompting when no episode exists")
  func mediaServicesResetRebuildsWithoutPromptingWhenNoEpisodeExists() async throws {
    try await LogCapture.withSink { sink in
      PlayHelpers.setupCommandHandling()
      await playManager.start()
      let initialAVPlayer = avPlayer
      let initialCallCount = await audioSession.configureCallCount
      #expect(sharedState.onDeck == nil)
      #expect(sharedState.playbackStatus == .stopped)

      notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
      try await Wait.until(
        { await avPlayer != initialAVPlayer },
        { "Expected new AVPlayer to be created" }
      )
      #expect(sharedState.onDeck == nil)
      #expect(sharedState.playbackStatus == .stopped)
      #expect(alert.config == nil)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
            }
        },
        { "Expected media-services reset telemetry" }
      )
      let telemetry = sink.captured()
        .filter {
          $0.level == .warning
            && $0.message.contains("event=mediaServicesResetHandled")
            && $0.message.contains("outcome=noEpisode")
        }
      #expect(telemetry.count == 1)
    }
  }

  @Test("media services reset preserves OnDeck when audio configuration fails")
  func mediaServicesResetPreservesOnDeckWhenAudioConfigurationFails() async throws {
    try await LogCapture.withSink { sink in
      PlayHelpers.setupCommandHandling()
      await playManager.start()
      let podcastEpisode = try await Create.podcastEpisode()

      try await PlayHelpers.load(podcastEpisode)
      try await PlayHelpers.pause()
      let initialAVPlayer = avPlayer
      let initialActivationCount = await audioSession.activeCalls.filter(\.self).count

      audioSession.configureError { $0 = TestError.simulatedFailure }

      notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await PlayHelpers.waitFor(.stopped)
      try await PlayHelpers.waitForOnDeck(nil)
      try await PlayHelpers.waitForQueue([podcastEpisode])
      try await Wait.until(
        { await avPlayer != initialAVPlayer },
        { "Expected new AVPlayer to be created" }
      )
      try await Wait.until(
        { @MainActor in alert.config?.title == "Couldn't start audio playback" },
        { @MainActor in "Expected alert after failed audio session reconfiguration" }
      )
      #expect(await audioSession.activeCalls.filter(\.self).count == initialActivationCount)
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
            }
        },
        { "Expected media-services reset telemetry" }
      )
      let telemetry = sink.captured()
        .filter {
          $0.level == .warning
            && $0.message.contains("event=mediaServicesResetHandled")
            && $0.message.contains("outcome=configurationFailed")
            && $0.message.contains("resumeEpisodeID=\(podcastEpisode.id)")
        }
      #expect(telemetry.count == 1)
    }
  }

  @Test("media services reset leaves an existing queue untouched until user action")
  func mediaServicesResetLeavesExistingQueueUntouchedUntilUserAction() async throws {
    PlayHelpers.setupCommandHandling()
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    try await queue.unshift(podcastEpisode.id)
    #expect(sharedState.onDeck == nil)

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    try await PlayHelpers.waitForQueue([podcastEpisode])
    #expect(sharedState.onDeck == nil)
    #expect(sharedState.playbackStatus == .stopped)
    try await Wait.until(
      { @MainActor in alert.config?.title == "Audio Services Restarted" },
      { @MainActor in "Expected an audio-services reset explanation" }
    )
    #expect(
      await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
        == initialLoadCount
    )
    #expect(await audioSession.activeCalls.filter(\.self).isEmpty)
  }

  @Test("media services reset treats an old load failure as debug context")
  func mediaServicesResetTreatsOldLoadFailureAsDebugContext() async throws {
    try await LogCapture.withSink { sink in
      PlayHelpers.setupCommandHandling()
      await playManager.start()
      let podcastEpisode = try await Create.podcastEpisode()

      await episodeAssetLoader.respond(
        to: podcastEpisode.episode.mediaURL,
        error: TestError.assetLoadFailure(podcastEpisode)
      )
      await #expect(throws: (any Error).self) {
        try await playManager.load(podcastEpisode)
      }

      notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
            }
        },
        { "Expected media-services reset telemetry" }
      )
      let settledLoadLogs = sink.captured()
        .filter {
          $0.message.contains("cancelLoadForMediaServicesReset: load task settled")
        }
      #expect(settledLoadLogs.map(\.level) == [.debug])
    }
  }

  @Test("media services reset cancels an in-flight load before rebuilding")
  func mediaServicesResetCancelsInFlightLoadBeforeRebuilding() async throws {
    PlayHelpers.setupCommandHandling()
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let loadStarted = AsyncSemaphore(value: 0)
    let finishLoading = AsyncSemaphore(value: 0)
    await episodeAssetLoader.respond(to: podcastEpisode.episode.mediaURL) { _ in
      loadStarted.signal()
      try await finishLoading.waitUnlessCancelled()
      return (true, .seconds(60))
    }

    let loadAndPlayTask = Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
    defer {
      loadAndPlayTask.cancel()
      finishLoading.signal()
    }

    await loadStarted.wait()
    let initialAVPlayer = avPlayer
    let configureCallCount = await audioSession.configureCallCount

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    try await PlayHelpers.waitForConfigureCallCount(atLeast: configureCallCount + 1)
    finishLoading.signal()

    await #expect(throws: CancellationError.self) {
      try await loadAndPlayTask.value
    }
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([podcastEpisode])
    try await PlayHelpers.waitForNoCurrentItem()
    try await Wait.until(
      { @MainActor in alert.config?.title == "Audio Services Restarted" },
      { @MainActor in "Expected an audio-services reset explanation" }
    )
  }

  @Test("media services reset disposes invalid player before restoring queue")
  func mediaServicesResetDisposesInvalidPlayerBeforeRestoringQueue() async throws {
    PlayHelpers.setupCommandHandling()
    await playManager.start()
    let resumeTime = CMTime.seconds(123)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: resumeTime)
    )

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitFor(resumeTime)
    try await PlayHelpers.pause()
    let initialAVPlayer = avPlayer
    let fakeQueue = try #require(queue as? FakeQueue)
    let unshiftStarted = AsyncSemaphore(value: 0)
    let finishUnshift = AsyncSemaphore(value: 0)
    fakeQueue.beforeUnshiftEpisode { episodeID in
      #expect(episodeID == podcastEpisode.id)
      unshiftStarted.signal()
      await finishUnshift.wait()
    }
    defer { finishUnshift.signal() }

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    await unshiftStarted.wait()
    #expect(initialAVPlayer.current == nil)
    #expect(initialAVPlayer.timeObservers.isEmpty)

    finishUnshift.signal()
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    try await PlayHelpers.waitForQueue([podcastEpisode])
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitFor(.stopped)
    let preservedEpisode = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    #expect(preservedEpisode.currentTime == resumeTime)
  }
}
