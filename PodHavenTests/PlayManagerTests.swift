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

@Suite("of PlayManager tests", .container)
@MainActor struct PlayManagerTests {
  @DynamicInjected(\.fakeAudioSession) private var audioSession
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeDataLoader) private var dataLoader
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var commandCenter: FakeCommandCenter {
    Container.shared.commandCenter() as! FakeCommandCenter
  }
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    await cacheManager.start()
    await playManager.start()
  }

  // MARK: - Loading

  @Test("loading sets all data")
  func loadingSetsAllData() async throws {
    dataLoader.setDefaultHandler { url in
      FakeDataLoader.create(url).pngData()!
    }
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck == podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)

    var expectedInfo: [String: Any] = [:]
    expectedInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    expectedInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    expectedInfo[MPMediaItemPropertyPlaybackDuration] = onDeck.duration.seconds
    expectedInfo[MPMediaItemPropertyTitle] = onDeck.episodeTitle
    if let pubDate = onDeck.pubDate {
      expectedInfo[MPMediaItemPropertyReleaseDate] = pubDate
    }
    expectedInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.mediaURL.rawValue
    expectedInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
    expectedInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
    expectedInfo[MPNowPlayingInfoPropertyExternalContentIdentifier] = onDeck.guid.rawValue
    expectedInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
    expectedInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
    expectedInfo[MPNowPlayingInfoPropertyPlaybackProgress] = 0.0
    expectedInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0

    // Check all keys exist in both dictionaries
    #expect(Set(nowPlayingInfo!.keys) == Set(expectedInfo.keys).union([MPMediaItemPropertyArtwork]))

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
      #expect(
        isEqual(nowPlayingInfo![key]!, expectedValue),
        """
        Key \(key) - \
        Expected: \(expectedValue), \
        Actual: \(String(describing: nowPlayingInfo![key]!))
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
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()

    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("loading an episode sets audio session active")
  func loadingEpisodeSetsAudioSessionActive() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.waitForAudioActive(false)
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForAudioActive(true)
  }

  @Test("finishing last episode sets audio session inactive")
  func finishingLastEpisodeSetsAudioSessionInactive() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitForAudioActive(true)

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForAudioActive(false)
  }

  @Test("episode failing makes audio session inactive")
  func episodeFailingMakesAudioSessionInactive() async throws {
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
    let (podcastEpisode, failingEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitForAudioActive(true)

    await episodeAssetLoader.respond(
      to: failingEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(failingEpisode)
    )
    _ = try? await playManager.load(failingEpisode)
    try await PlayHelpers.waitForAudioActive(false)
  }

  @Test("loading an episode sets loading status")
  func loadingEpisodeSetsLoadingStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let loadingSemaphore = await episodeAssetLoader.waitThenRespond(
      to: podcastEpisode.episode.mediaURL,
      data: (true, .seconds(10))
    )

    Task { try await playManager.load(podcastEpisode) }
    try await PlayHelpers.waitFor(.loading(podcastEpisode.episode.title))

    loadingSemaphore.signal()
    try await PlayHelpers.waitFor(.waiting)
  }

  @Test("loading an episode seeks to its stored time")
  func loadingEpisodeSeeksToItsStoredTime() async throws {
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
    dataLoader.setDefaultHandler { url in
      FakeDataLoader.create(url).pngData()!
    }
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(
      onDeck.image!
        .isVisuallyEqual(to: try await imagePipeline.image(for: podcastEpisode.image))
    )
  }

  @Test("loading failure clears state")
  func loadingFailureClearsState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    await episodeAssetLoader.respond(
      to: podcastEpisode.episode.mediaURL,
      error: TestError.assetLoadFailure(podcastEpisode)
    )
    await #expect(throws: (any Error).self) {
      try await playManager.load(podcastEpisode)
    }

    try await PlayHelpers.waitFor(.stopped)
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("loading failure with existing episode clears state")
  func loadingFailureWithExistingEpisodeClearsState() async throws {
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
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("loading cancels any in-progress load")
  func loadingCancelsAnyInProgressLoad() async throws {
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

  @Test("loading during image fetching cancels any in-progress load")
  func loadingDuringImageFetchingCancelsAnyInProgressLoad() async throws {
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.executeMidImageFetch(for: originalEpisode.image) {
      await dataLoader.clearCustomHandler(for: originalEpisode.image)
      try await playManager.load(incomingEpisode)
    }

    await #expect(throws: (any Error).self) {
      try await playManager.load(originalEpisode)
    }

    try await PlayHelpers.waitForQueue([originalEpisode])
    try await PlayHelpers.waitForCurrentItem(incomingEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
  }

  @Test("loading and playing during load does not result in stopped playState")
  func loadingAndPlayingDuringLoadDoesNotResultInStoppedPlayState() async throws {
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

  @Test("playing while loading retains playing status")
  func playingWhileLoadingRetainsPlayingStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.executeMidLoad(for: podcastEpisode.episode.mediaURL) {
      await playManager.play()
    }
    try await playManager.load(podcastEpisode)

    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(podcastEpisode)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("loading episode already loaded does nothing")
  func loadingEpisodeAlreadyLoadedDoesNothing() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    #expect(try await playManager.load(podcastEpisode) == false)
  }

  @Test("loading race condition with success after failure does not result in stopped playState")
  func loadingRaceConditionWithSuccessAfterFailureDoesNotResultInStoppedPlayState() async throws {
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    let originalSemaphore = await episodeAssetLoader.waitThenRespond(
      to: originalEpisode.episode.mediaURL,
      error: PlaybackError.mediaNotPlayable(originalEpisode)
    )
    let incomingSemaphore = await episodeAssetLoader.waitThenRespond(
      to: incomingEpisode.episode.mediaURL,
      data: (true, CMTime.seconds(60))
    )
    async let _ = playManager.load(originalEpisode)
    try await PlayHelpers.waitFor(.loading(originalEpisode.episode.title))
    async let incomingLoad = playManager.load(incomingEpisode)
    originalSemaphore.signal()
    try await PlayHelpers.waitFor(.stopped)
    incomingSemaphore.signal()
    _ = try await incomingLoad
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
  }

  // MARK: - Playback Controls

  @Test("play and pause functions play and pause playback")
  func playAndPauseFunctionsPlayAndPausePlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)

    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)
  }

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    commandCenter.play()
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)

    commandCenter.pause()
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)

    commandCenter.togglePlayPause()
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)

    commandCenter.togglePlayPause()
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)

    commandCenter.skipForward(TimeInterval.seconds(2))
    try await PlayHelpers.waitFor(CMTime.seconds(2))

    commandCenter.skipBackward(TimeInterval.seconds(1))
    try await PlayHelpers.waitFor(CMTime.seconds(1))

    commandCenter.seek(to: TimeInterval.seconds(5))
    try await PlayHelpers.waitFor(CMTime.seconds(5))
  }

  @Test("seek commands are ignored during episode finish")
  func seekCommandsAreIgnoredDuringEpisodeFinish() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish episode which should start ignoring seek commands
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForIgnoringSeek()
    commandCenter.seek(to: .seconds(5))
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    commandCenter.seek(to: .seconds(5))
    try await PlayHelpers.waitFor(.zero)

    // Advance time to end the halt period
    await sleeper.advanceTime(by: .seconds(2))
    try await PlayHelpers.waitForNotIgnoringSeek()
    commandCenter.seek(to: .seconds(10))
    try await PlayHelpers.waitFor(.seconds(10))
  }

  @Test("audio session interruption stops and restarts playback")
  func audioSessionInterruptionStopsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let interruptionContinuation = notifier.continuation(
      for: AVAudioSession.interruptionNotification
    )

    // Interruption began: pause playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
      )
    )
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)

    // Interruption ended: resume playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
          AVAudioSessionInterruptionOptionKey:
            AVAudioSession.InterruptionOptions.shouldResume.rawValue,
        ]
      )
    )
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)
  }

  @Test("time update events update currentTime")
  func timeUpdateEventsUpdateCurrentTime() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let advancedTime = CMTime.seconds(10)
    avPlayer.advanceTime(to: advancedTime)
    try await PlayHelpers.waitFor(advancedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == advancedTime)
  }

  @Test("waiting to play time control status updates playstate")
  func waitingToPlayTimeControlStatusUpdatesPlaystate() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    avPlayer.waitingToPlay()
    try await PlayHelpers.waitFor(.waiting)
  }

  // MARK: - Seeking

  @Test("seeking updates current time")
  func seekingUpdatesCurrentTime() async throws {
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

    let skipAmount = CMTime.seconds(30)
    let skipTime = CMTimeAdd(originalTime, skipAmount)
    await playManager.seekForward(skipAmount)
    try await PlayHelpers.waitFor(skipTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == skipTime)
    #expect(PlayHelpers.nowPlayingProgress == skipTime.seconds / duration.seconds)

    let rewindAmount = CMTime.seconds(15)
    let rewindTime = CMTimeSubtract(skipTime, rewindAmount)
    await playManager.seekBackward(rewindAmount)
    try await PlayHelpers.waitFor(rewindTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == rewindTime)
    #expect(PlayHelpers.nowPlayingProgress == rewindTime.seconds / duration.seconds)
  }

  @Test("time update events are ignored while seeking")
  func timeUpdateEventsAreIgnoredWhileSeeking() async throws {
    let (failedEpisode, successfulEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(failedEpisode)

    // After this failed seek, all time advancement is being ignored
    avPlayer.seekHandler = { _ in false }
    let failedSeekTime = CMTime.seconds(60)
    await playManager.seek(to: failedSeekTime)
    #expect(!PlayHelpers.hasPeriodicTimeObservation())

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

  // MARK: - Queue Management

  @Test("loading an episode removes it from the queue")
  func loadingAnEpisodeRemovesItFromQueue() async throws {
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
    let (playingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await playManager.load(playingEpisode)
    try await playManager.load(incomingEpisode)

    try await PlayHelpers.waitForQueue([playingEpisode])
    try await PlayHelpers.waitForCurrentItem(incomingEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
  }

  @Test("loading failure unshifts onto queue")
  func loadingFailureUnshiftsOntoQueue() async throws {
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
    let originalEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.executeMidImageFetch(for: originalEpisode.image) {
      await dataLoader.clearCustomHandler(for: originalEpisode.image)
      try await playManager.load(originalEpisode)
    }
    await #expect(throws: (any Error).self) {
      try await playManager.load(originalEpisode)
    }

    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForCurrentItem(originalEpisode.episode.mediaURL)
    try await PlayHelpers.waitForOnDeck(originalEpisode)
  }

  @Test("failed episode gets unshifted back to queue")
  func failedEpisodeGetsUnshiftedBackToQueue() async throws {
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

  // MARK: - Episode Finishing

  @Test("finishing last episode with nothing queued clears state")
  func finishingLastEpisodeWithNothingQueuedClearsState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    avPlayer.finishEpisode()

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForNoCurrentItem()
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
  }

  @Test("finishing last episode will load next episode")
  func finishingLastEpisodeWillLoadNextEpisode() async throws {
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
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForFinished(podcastEpisode)
  }

  // MARK: - Cache Functionality

  @Test("loading episode with cached media uses cached URL")
  func loadingEpisodeWithCachedMediaUsesCachedURL() async throws {
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
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.waitForCurrentItem(podcastEpisode.episode.mediaURL)

    // Verify the asset was loaded with the original media URL
    let currentItem = avPlayer.current! as! FakeAVPlayerItem
    #expect(currentItem.url == podcastEpisode.episode.mediaURL.rawValue)
  }

  @Test("loading episode falls back to original URL if cached media URL fails")
  func loadingEpisodeFallsBackToOriginalURLIfCachedMediaURLFails() async throws {
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
    let podcastEpisode = try await Create.podcastEpisode()
    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)
    try await CacheHelpers.waitForCached(podcastEpisode.id)

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitForQueue([])

    try await CacheHelpers.waitForCached(podcastEpisode.id)
  }

  @Test("episode cache is cleared when playing to end")
  func episodeCacheIsClearedWhenPlayingToEnd() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let taskID = try await CacheHelpers.unshiftToQueue(podcastEpisode.id)
    try await CacheHelpers.simulateBackgroundFinish(taskID)

    let fileName = try await CacheHelpers.waitForCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFile(fileName)

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()
    avPlayer.finishEpisode()

    try await CacheHelpers.waitForNotCached(podcastEpisode.id)
    try await CacheHelpers.waitForCachedFileRemoved(fileName)
  }

  // MARK: - Media Services Reset

  @Test("media services reset notification restores to playing")
  func mediaServicesResetNotificationRestoresToPlaying() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    // Load and start playing an episode
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()

    // Verify initial state
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    // Verify audio session was reconfigured
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)

    // Verify new AVPlayer is created
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )

    // Verify the episode was reloaded (asset loader called again)
    try await PlayHelpers.waitForLoadResponse(
      for: podcastEpisode.episode.mediaURL,
      count: initialLoadCount + 1
    )

    // Verify onDeck is restored properly
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Verify playback state is restored to playing
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("media services reset notification restores to waiting")
  func mediaServicesResetNotificationRestoresPlaybackState() async throws {
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
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await PlayHelpers.waitForLoadResponse(
      for: podcastEpisode.episode.mediaURL,
      count: initialLoadCount + 1
    )

    // Verify onDeck is restored properly
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Verify playback state is restored to paused
    try await PlayHelpers.waitFor(.waiting)
  }

  @Test("media services reset notification handles recent failure state")
  func mediaServicesResetNotificationHandlesRecentFailureState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    let initialLoadCount = await episodeAssetLoader.responseCount(
      for: podcastEpisode.episode.mediaURL
    )

    // Now simulate the podcastEpisode failing after it becomes currentItem
    let currentItem = avPlayer.current as! FakeAVPlayerItem
    currentItem.setStatus(.failed)
    try await PlayHelpers.waitForOnDeck(nil)
    try await PlayHelpers.waitFor(.stopped)

    // Trigger media services reset notification (should use recent failure info)
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    // Verify audio session was reconfigured
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)

    // Verify new AVPlayer is created
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )

    // Verify the episode was reloaded (asset loader called again)
    try await PlayHelpers.waitForLoadResponse(
      for: podcastEpisode.episode.mediaURL,
      count: initialLoadCount + 1
    )

    // Verify onDeck is restored properly
    try await PlayHelpers.waitForOnDeck(podcastEpisode)

    // Verify playback state is restored to playing
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("media services reset notification with no episode does nothing")
  func mediaServicesResetNotificationWithNoEpisodeDoesNothing() async throws {
    // Start with no episode loaded
    let initialAVPlayer = avPlayer
    let initialCallCount = await audioSession.configureCallCount
    #expect(playState.onDeck == nil)
    #expect(playState.status == .stopped)

    // Trigger media services reset notification
    notifier.continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))

    // Call count goes up, podAVPlayer reset, but nothing else changes.
    try await PlayHelpers.waitForConfigureCallCount(callCount: initialCallCount + 1)
    try await Wait.until(
      { await avPlayer != initialAVPlayer },
      { "Expected new AVPlayer to be created" }
    )
    #expect(playState.onDeck == nil)
    #expect(playState.status == .stopped)
  }
}
