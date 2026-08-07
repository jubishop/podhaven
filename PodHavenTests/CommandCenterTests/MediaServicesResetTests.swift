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

  @Test("media services reset preserves OnDeck and waits for user to reload")
  func mediaServicesResetPreservesOnDeckAndWaitsForUserToReload() async throws {
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
      try await PlayHelpers.waitForOnDeck(podcastEpisode)
      try await PlayHelpers.waitFor(.stopped)
      try await PlayHelpers.waitForQueue([podcastEpisode, queuedEpisode])
      #expect(sharedState.currentEpisodeID == podcastEpisode.id)
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

      await playManager.play()
      try await PlayHelpers.waitFor(.playing)
      try await PlayHelpers.waitFor(resumeTime)
      try await PlayHelpers.waitForQueue([queuedEpisode])
      #expect(
        await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
          == initialLoadCount + 1
      )
      try await Wait.until(
        { await audioSession.activeCalls.filter(\.self).count == initialActivationCount + 1 },
        { "Expected user-initiated load to reactivate the audio session" }
      )
    }
  }

  @Test("failed user recovery keeps the interrupted episode OnDeck")
  func failedUserRecoveryKeepsInterruptedEpisodeOnDeck() async throws {
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
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([podcastEpisode])

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    await playManager.play()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(resumeTime)
    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([podcastEpisode])
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    #expect(
      await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
        == initialLoadCount + 1
    )
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
      try await PlayHelpers.waitForOnDeck(podcastEpisode)
      try await PlayHelpers.waitForQueue([podcastEpisode])
      #expect(sharedState.currentEpisodeID == podcastEpisode.id)
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

  @Test("media services reset does not prompt when only a queued episode exists")
  func mediaServicesResetDoesNotPromptWhenOnlyQueuedEpisodeExists() async throws {
    try await LogCapture.withSink { sink in
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
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
                && $0.message.contains("outcome=queueStateUnknown")
            }
        },
        { "Expected idle media-services reset telemetry" }
      )

      #expect(sharedState.onDeck == nil)
      #expect(sharedState.playbackStatus == .stopped)
      #expect(alert.config == nil)
      #expect(
        await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
          == initialLoadCount
      )
      #expect(await audioSession.activeCalls.filter(\.self).isEmpty)
    }
  }

  @Test("media services reset marks a prior item failure as ambiguous queue state")
  func mediaServicesResetMarksPriorItemFailureAsAmbiguousQueueState() async throws {
    try await LogCapture.withSink { sink in
      PlayHelpers.setupCommandHandling()
      await playManager.start()
      let podcastEpisode = try await Create.podcastEpisode()

      try await PlayHelpers.load(podcastEpisode)
      try await PlayHelpers.pause()
      let initialAVPlayer = avPlayer
      let initialLoadCount = await episodeAssetLoader.responseCount(
        for: podcastEpisode.episode.mediaURL
      )
      let initialActivationCount = await audioSession.activeCalls.filter(\.self).count
      let currentItem = try #require(initialAVPlayer.current as? FakeAVPlayerItem)

      currentItem.setStatus(.failed)
      try await PlayHelpers.waitForOnDeck(nil)
      try await PlayHelpers.waitFor(.stopped)
      try await PlayHelpers.waitForQueue([podcastEpisode])

      let initialConfigureCallCount = await audioSession.configureCallCount
      notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await PlayHelpers.waitForConfigureCallCount(
        callCount: initialConfigureCallCount + 1
      )
      try await Wait.until(
        { await avPlayer != initialAVPlayer },
        { "Expected new AVPlayer to be created" }
      )
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
            && $0.message.contains("outcome=queueStateUnknown")
            && $0.message.contains("interruptedEpisodeID=nil")
            && $0.message.contains("resumeEpisodeID=\(podcastEpisode.id)")
        }
      #expect(telemetry.count == 1)

      try await PlayHelpers.waitForQueue([podcastEpisode])
      #expect(sharedState.onDeck == nil)
      #expect(sharedState.playbackStatus == .stopped)
      #expect(alert.config == nil)
      #expect(
        await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL)
          == initialLoadCount
      )
      #expect(await audioSession.activeCalls.filter(\.self).count == initialActivationCount)
    }
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
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.stopped)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    let preservedEpisode = try #require(try await repo.podcastEpisode(podcastEpisode.id))
    #expect(preservedEpisode.currentTime == resumeTime)
  }
}

@Suite("of cold-launch media services reset tests", .container)
@MainActor struct MediaServicesResetColdLaunchTests {
  @Test("media services reset preserves persisted identity before restoration")
  func mediaServicesResetPreservesPersistedIdentityBeforeRestoration() async throws {
    try await LogCapture.withSink { sink in
      let podcastEpisode = try await Create.podcastEpisode(
        Create.unsavedEpisode(currentTime: .seconds(123))
      )
      podcastEpisode.id.store(
        to: Container.shared.standardDefaults(),
        forKey: "currentEpisodeID"
      )

      let sharedState = Container.shared.sharedState()
      let queue = Container.shared.queue()
      let audioSession = Container.shared.fakeAudioSession()
      let episodeAssetLoader = Container.shared.fakeEpisodeAssetLoader()
      let alert = Container.shared.alert()
      let initialAVPlayer = Container.shared.avPlayer() as! FakeAVPlayer
      let initialConfigureCallCount = await audioSession.configureCallCount

      PlayHelpers.setupCommandHandling()
      #expect(sharedState.currentEpisodeID == podcastEpisode.id)
      #expect(sharedState.onDeck == nil)

      Container.shared.notifier()
        .continuation(for: AVAudioSession.mediaServicesWereResetNotification)
        .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

      try await PlayHelpers.waitForConfigureCallCount(
        callCount: initialConfigureCallCount + 1
      )
      try await Wait.until(
        { @MainActor in Container.shared.avPlayer() as! FakeAVPlayer != initialAVPlayer },
        { "Expected new AVPlayer to be created" }
      )
      try await Wait.until(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=mediaServicesResetHandled")
            }
        },
        { "Expected media-services reset telemetry" }
      )

      let queuedEpisode = try await queue.nextEpisode
      #expect(queuedEpisode?.id == podcastEpisode.id)
      #expect(sharedState.currentEpisodeID == podcastEpisode.id)
      #expect(sharedState.onDeck == nil)
      #expect(
        await episodeAssetLoader.responseCount(for: podcastEpisode.episode.mediaURL) == 0
      )
      #expect(await audioSession.activeCalls.filter(\.self).isEmpty)
      try await Wait.until(
        { @MainActor in alert.config?.title == "Audio Services Restarted" },
        { @MainActor in "Expected an audio-services reset explanation" }
      )
    }
  }
}
