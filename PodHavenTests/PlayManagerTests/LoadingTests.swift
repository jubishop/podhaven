// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Nuke
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Loading tests", .container)
@MainActor struct LoadingTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeDataLoader) private var dataLoader
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.imagePipeline) private var imagePipeline
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

  // MARK: - Loading

  @Test("loading sets all data")
  func loadingSetsAllData() async throws {
    userSettings.$nextTrackBehavior.new(.nextEpisode)

    await playManager.start()
    dataLoader.setDefaultHandler { url in
      FakeDataLoader.create(url).pngData()!
    }
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.id == podcastEpisode.id)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeckArtwork()

    var expectedInfo: [String: Any] = [:]
    expectedInfo[MPMediaItemPropertyAlbumTitle] = onDeck.podcastTitle
    expectedInfo[MPMediaItemPropertyArtist] = onDeck.podcastTitle
    expectedInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    expectedInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    expectedInfo[MPMediaItemPropertyPlaybackDuration] = onDeck.duration.seconds
    expectedInfo[MPMediaItemPropertyTitle] = onDeck.title
    expectedInfo[MPMediaItemPropertyReleaseDate] = onDeck.pubDate
    expectedInfo[MPNowPlayingInfoPropertyPlaybackQueueIndex] = 0
    expectedInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.mediaURL.rawValue
    expectedInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    expectedInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
    expectedInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] = onDeck.mediaGUID.guid.rawValue
    expectedInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    expectedInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    expectedInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0.0
    expectedInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
    expectedInfo[MPNowPlayingInfoPropertyPlaybackQueueCount] = 1

    #expect(
      Set(nowPlayingInfo!.keys)
        == Set(expectedInfo.keys).union([MPMediaItemPropertyArtwork])
    )

    let isEqual: (Any?, Any) -> Bool = { lhs, rhs in
      switch (lhs, rhs) {
      case (let lhs as String, let rhs as String): return lhs == rhs
      case (let lhs as Double, let rhs as Double): return lhs == rhs
      case (let lhs as UInt, let rhs as UInt): return lhs == rhs
      case (let lhs as Int, let rhs as Int): return lhs == rhs
      case (let lhs as Bool, let rhs as Bool): return lhs == rhs
      case (let lhs as URL, let rhs as URL): return lhs == rhs
      case (let lhs as Date, let rhs as Date): return lhs == rhs
      default: return false
      }
    }

    // Check each value (except artwork which needs special handling)
    for (key, expectedValue) in expectedInfo {
      let actualValue = nowPlayingInfo![key] ?? nil
      #expect(
        isEqual(actualValue, expectedValue),
        """
        Key \(key) - \
        Expected: \(expectedValue), \
        Actual: \(String(describing: actualValue))
        """
      )
    }

    // Check artwork separately
    if let actualArtwork = nowPlayingInfo![MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
      let image = try await imagePipeline.image(for: podcastEpisode.image)
      let actualImage = actualArtwork.image(at: image.size)!
      #expect(actualImage.isVisuallyEqual(to: image))
    } else {
      Issue.record("MPMediaItemPropertyArtwork is missing or wrong type")
    }
  }

  @Test("loading and playing immediately works")
  func loadingAndPlayingImmediatelyWorks() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()

    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("loading an episode sets audio session active")
  func loadingEpisodeSetsAudioSessionActive() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.waitForAudioActive(false)
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForAudioActive(true)
  }

  @Test("finishing last episode sets audio session inactive")
  func finishingLastEpisodeSetsAudioSessionInactive() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitForAudioActive(true)

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForAudioActive(false)
  }

  @Test("episode failing makes audio session inactive")
  func episodeFailingMakesAudioSessionInactive() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitForAudioActive(true)

    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    let currentItem = avPlayer.current as! FakeAVPlayerItem
    currentItem.setStatus(.failed)
    try await PlayHelpers.waitForAudioActive(false)
  }

  @Test("failing to load episode makes audio session inactive")
  func failingToLoadEpisodeMakesAudioSessionInactive() async throws {
    await playManager.start()
    let (podcastEpisode, failingEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitForAudioActive(true)

    await episodeAssetLoader.respond(
      to: failingEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(failingEpisode)
    )
    do { try await playManager.load(failingEpisode) } catch { /* expected */  }
    try await PlayHelpers.waitForAudioActive(false)
  }

  @Test("loading an episode sets loading status")
  func loadingEpisodeSetsLoadingStatus() async throws {

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    let loadingSemaphore = await episodeAssetLoader.waitRespond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, .seconds(10))
    )

    let loadTask = Task { try await playManager.load(podcastEpisode) }
    defer {
      loadTask.cancel()
      loadingSemaphore.signal()
    }
    try await PlayHelpers.waitFor(.loading(podcastEpisode.episode.title))

    loadingSemaphore.signal()
    #expect(try await loadTask.value == true)
    #expect(sharedState.playbackStatus == .paused)
  }

  @Test("loading an episode seeks to its stored time")
  func loadingEpisodeSeeksToItsStoredTime() async throws {
    await playManager.start()
    let currentTime: CMTime = .seconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: currentTime)
    )

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitFor(currentTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == currentTime)
  }

  @Test("loading an episode updates its duration value")
  func loadingEpisodeUpdatesDuration() async throws {
    await playManager.start()
    let originalDuration = CMTime.seconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: originalDuration)
    )

    let correctDuration = CMTime.seconds(20)
    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, correctDuration)
    )

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.duration == correctDuration)

    let updatedPodcastEpisode: Episode? = try await repo.episode(podcastEpisode.id)
    #expect(updatedPodcastEpisode?.duration == correctDuration)
  }

  @Test("loading fetches episode image if it exists")
  func loadingFetchesEpisodeImageIfItExists() async throws {

    await playManager.start()
    dataLoader.setDefaultHandler { url in
      FakeDataLoader.create(url).pngData()!
    }
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    _ = try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForOnDeckArtwork()
    #expect(
      sharedState.onDeck!.artwork!
        .isVisuallyEqual(to: try await imagePipeline.image(for: podcastEpisode.image))
    )
  }

  @Test("loading failure clears state")
  func loadingFailureClearsState() async throws {
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
    #expect(sharedState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("loading completes and sets onDeck even when image fetch is stuck")
  func loadingCompletesAndSetsOnDeckEvenWhenImageFetchIsStuck() async throws {
    await playManager.start()

    // Create an episode with an image URL
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    // Set up image loader that never completes
    let imageLoadingStarted = AsyncSemaphore(value: 0)
    let neverSignals = AsyncSemaphore(value: 0)
    dataLoader.respond(to: podcastEpisode.image) { _ in
      imageLoadingStarted.signal()
      await neverSignals.wait()
      return Data()
    }

    // Load the episode
    try await playManager.load(podcastEpisode)

    // Wait for image loading to start (confirms fetchImage was called)
    await imageLoadingStarted.wait()

    // Status should progress to paused even though image is stuck
    try await PlayHelpers.waitFor(.paused)

    // Episode should be set in onDeck even without artwork
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Confirm artwork is not set (since image fetch is stuck)
    #expect(sharedState.onDeck?.artwork == nil)
  }

  @Test("loading failure with existing episode clears state")
  func loadingFailureWithExistingEpisodeClearsState() async throws {
    await playManager.start()
    let (playingEpisode, episodeToLoad) = try await Create.twoPodcastEpisodes()

    try await playManager.load(playingEpisode)
    await episodeAssetLoader.respond(
      to: episodeToLoad.episode.mediaURL,
      error: TestError.assetLoadFailure(episodeToLoad)
    )
    await #expect(throws: (any Error).self) {
      try await playManager.load(episodeToLoad)
    }

    try await PlayHelpers.waitFor(.stopped)
    #expect(sharedState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("loading cancels any in-progress load")
  func loadingCancelsAnyInProgressLoad() async throws {
    await playManager.start()
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers
      .executeMidLoad(for: originalEpisode.episode.mediaURL) { @MainActor in
        await episodeAssetLoader.clearCustomHandler(for: originalEpisode.episode)
        try await playManager.load(incomingEpisode)
      }

    await #expect(throws: (any Error).self) {
      try await playManager.load(originalEpisode)
    }

    try await PlayHelpers.waitForQueue([originalEpisode])
    try await PlayHelpers.waitForCurrentItem(incomingEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
  }

  @Test("loading during image fetching cancels previous image fetch")
  func loadingDuringImageFetchingCancelsPreviousImageFetch() async throws {

    await playManager.start()

    // Create episodes with distinct image URLs
    let originalEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(image: URL.valid())
    )
    let incomingEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(image: URL.valid())
    )

    // Use maximally different colors to avoid false positives
    let whiteImage = FakeDataLoader.createSolidColor(.white)
    let blackImage = FakeDataLoader.createSolidColor(.black)

    dataLoader.respond(to: originalEpisode.image, data: whiteImage.pngData()!)
    dataLoader.respond(to: incomingEpisode.image, data: blackImage.pngData()!)

    // Set up to load incoming episode during original's image fetch
    try await PlayHelpers.executeMidImageFetch(for: originalEpisode.image, uiImage: whiteImage) {
      try await playManager.load(incomingEpisode)
    }

    // Load original - triggers image fetch which gets intercepted
    // Note: no longer throws since image fetch is async
    try await playManager.load(originalEpisode)

    // Verify incoming episode is on deck with its artwork
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitForOnDeckArtwork()

    // Confirm artwork is black (incoming's), not white (original's)
    let artworkColor = FakeDataLoader.pixelColor(of: sharedState.onDeck!.artwork!)
    #expect(FakeDataLoader.colorsApproximatelyEqual(artworkColor, .black))
    #expect(!FakeDataLoader.colorsApproximatelyEqual(artworkColor, .white))
  }

  @Test("loading and playing during load does not result in stopped playbackStatus")
  func loadingAndPlayingDuringLoadDoesNotResultInStoppedPlaybackStatus() async throws {
    await playManager.start()
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.executeMidLoad(for: originalEpisode.episode.mediaURL) {
      await episodeAssetLoader.clearCustomHandler(for: originalEpisode.episode)
      try await playManager.load(incomingEpisode)
      try await PlayHelpers.play()
    }

    await #expect(throws: (any Error).self) {
      try await playManager.load(originalEpisode)
    }

    try await PlayHelpers.waitFor(.playing)
  }

  @Test("new play survives cancellation cleanup from prior load")
  func newPlaySurvivesCancellationCleanupFromPriorLoad() async throws {
    await playManager.start()
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    let originalSemaphore = await episodeAssetLoader.waitRespond(
      to: originalEpisode.episode.mediaURL
    )
    let incomingSemaphore = await episodeAssetLoader.waitRespond(
      to: incomingEpisode.episode.mediaURL
    )
    let originalPlay = Task { try await playManager.play(originalEpisode) }
    defer {
      originalPlay.cancel()
      originalSemaphore.signal()
    }
    try await PlayHelpers.waitFor(.loading(originalEpisode.episode.title))

    let incomingPlay = Task { try await playManager.play(incomingEpisode) }
    defer {
      incomingPlay.cancel()
      incomingSemaphore.signal()
    }
    try await PlayHelpers.waitFor(.loading(incomingEpisode.episode.title))
    await #expect(throws: (any Error).self) {
      try await originalPlay.value
    }

    incomingSemaphore.signal()
    try await incomingPlay.value
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("audio session failure during load clears state and surfaces alert")
  func audioSessionFailureDuringLoadClearsStateAndSurfacesAlert() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    audioSession.configureError { $0 = TestError.simulatedFailure }

    let loaded = try await playManager.load(podcastEpisode)
    #expect(loaded == false)

    try await PlayHelpers.waitFor(.stopped)
    #expect(sharedState.onDeck == nil)
    #expect(nowPlayingInfo == nil)

    try await Wait.until(
      { @MainActor in alert.config != nil },
      { @MainActor in "Expected alert after audio session configuration failure" }
    )
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
    await playManager.play()

    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    #expect(sharedState.onDeck == nil)

    audioSession.activationError { $0 = nil }
    await playManager.restorePersistedEpisodeForForeground()

    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)
    try await PlayHelpers.waitForQueue([])
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

  @Test("audio session recovers on next load attempt after prior failure")
  func audioSessionRecoversOnNextLoadAttemptAfterPriorFailure() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    audioSession.configureError { $0 = TestError.simulatedFailure }
    #expect(try await playManager.load(podcastEpisode) == false)
    try await PlayHelpers.waitFor(.stopped)

    audioSession.configureError { $0 = nil }
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.paused)
  }

  @Test("loading episode already loaded does nothing")
  func loadingEpisodeAlreadyLoadedDoesNothing() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    #expect(try await playManager.load(podcastEpisode) == false)
  }

  @Test("earlier load failure does not stop newer load")
  func earlierLoadFailureDoesNotStopNewerLoad() async throws {
    await playManager.start()
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    let originalSemaphore = await episodeAssetLoader.waitRespond(
      to: originalEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(originalEpisode)
    )
    let incomingSemaphore = await episodeAssetLoader.waitRespond(
      to: incomingEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(60))
    )
    let originalLoad = Task { try await playManager.load(originalEpisode) }
    defer {
      originalLoad.cancel()
      originalSemaphore.signal()
    }
    try await PlayHelpers.waitFor(.loading(originalEpisode.episode.title))
    let incomingLoad = Task { try await playManager.load(incomingEpisode) }
    defer {
      incomingLoad.cancel()
      incomingSemaphore.signal()
    }
    try await PlayHelpers.waitFor(.loading(incomingEpisode.episode.title))
    originalSemaphore.signal()
    await #expect(throws: (any Error).self) {
      try await originalLoad.value
    }
    #expect(sharedState.playbackStatus == .loading(incomingEpisode.episode.title))
    incomingSemaphore.signal()
    #expect(try await incomingLoad.value == true)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
  }
}
