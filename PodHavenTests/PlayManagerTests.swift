// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Semaphore
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
@MainActor struct PlayManagerTests {
  @DynamicInjected(\.episodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.images) private var images
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var avQueuePlayer: FakeAVQueuePlayer {
    Container.shared.avQueuePlayer() as! FakeAVQueuePlayer
  }
  private var commandCenter: FakeCommandCenter {
    Container.shared.commandCenter() as! FakeCommandCenter
  }
  private var nowPlayingInfo: [String: Any?]? {
    Container.shared.mpNowPlayingInfoCenter().nowPlayingInfo
  }

  init() async throws {
    await playManager.start()
  }

  // MARK: - Loading

  @Test("loading sets all data")
  func loadingSetsAllData() async throws {
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck == podcastEpisode)
    try await PlayHelpers.waitForItemQueue([podcastEpisode])

    var expectedInfo: [String: Any] = [:]
    expectedInfo[MPMediaItemPropertyPodcastTitle] = onDeck.podcastTitle
    expectedInfo[MPMediaItemPropertyMediaType] = MPMediaType.podcast.rawValue
    expectedInfo[MPMediaItemPropertyPlaybackDuration] = onDeck.duration.seconds
    expectedInfo[MPMediaItemPropertyTitle] = onDeck.episodeTitle
    if let pubDate = onDeck.pubDate {
      expectedInfo[MPMediaItemPropertyReleaseDate] = pubDate
    }
    expectedInfo[MPNowPlayingInfoPropertyAssetURL] = onDeck.media.rawValue
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
      case let (lhs as String, rhs as String): return lhs == rhs
      case let (lhs as Double, rhs as Double): return lhs == rhs
      case let (lhs as UInt, rhs as UInt): return lhs == rhs
      case let (lhs as Int, rhs as Int): return lhs == rhs
      case let (lhs as Bool, rhs as Bool): return lhs == rhs
      case let (lhs as URL, rhs as URL): return lhs == rhs
      case let (lhs as Date, rhs as Date): return lhs == rhs
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
        Actual: \(String(describing: nowPlayingInfo![key]))
        """
      )
    }

    // Check artwork separately
    if let actualArtwork = nowPlayingInfo![MPMediaItemPropertyArtwork] as? MPMediaItemArtwork {
      let image = try await images.fetchImage(podcastEpisode.podcast.image)
      let actualImage = actualArtwork.image(at: image.size)!
      #expect(actualImage.isVisuallyEqual(to: image))
    } else {
      Issue.record("MPMediaItemPropertyArtwork is missing or wrong type")
    }
  }

  @Test("loading and playing immediately")
  func loadingAndPlayingImmediately() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()

    try await PlayHelpers.waitForObservations()
    try await PlayHelpers.waitForItemQueue([podcastEpisode])
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("loading an episode seeks to its stored time")
  func loadingEpisodeSeeksToItsStoredTime() async throws {
    let currentTime: CMTime = .inSeconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: currentTime)
    )

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.waitFor(currentTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == currentTime)
  }

  @Test("loading an episode updates its duration value")
  func loadingEpisodeUpdatesDuration() async throws {
    let originalDuration = CMTime.inSeconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: originalDuration)
    )

    let correctDuration = CMTime.inSeconds(20)
    episodeAssetLoader.respond(to: podcastEpisode.episode.media) { _ in (true, correctDuration) }

    let onDeck = try await PlayHelpers.load(podcastEpisode)
    #expect(onDeck.duration == correctDuration)

    let updatedPodcastEpisode = try await repo.episode(podcastEpisode.id)
    #expect(updatedPodcastEpisode?.episode.duration == correctDuration)
  }

  @Test("loading failure clears state")
  func loadingFailureClearsState() async throws {
    let episodeToLoad = try await Create.podcastEpisode()

    episodeAssetLoader.respond(to: episodeToLoad.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }
    await #expect(throws: (any Error).self) {
      try await PlayHelpers.load(episodeToLoad)
    }

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([episodeToLoad])
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(PlayHelpers.itemQueueURLs.isEmpty)
  }

  @Test("loading failure with existing episode fills queue")
  func loadingFailureWithExistingEpisodeFillsQueue() async throws {
    let (playingEpisode, episodeToLoad) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.load(playingEpisode)
    episodeAssetLoader.respond(to: episodeToLoad.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }
    await #expect(throws: (any Error).self) {
      try await PlayHelpers.load(episodeToLoad)
    }

    try await PlayHelpers.waitFor(.stopped)
    try await PlayHelpers.waitForQueue([episodeToLoad, playingEpisode])
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(PlayHelpers.itemQueueURLs.isEmpty)
  }

  @Test("loading cancels any in-progress load")
  func loadingCancelsAnyInProgressLoad() async throws {
    let (originalEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.executeMidLoad(for: originalEpisode) { @MainActor in
      try await PlayHelpers.load(incomingEpisode)
      episodeAssetLoader.clearCustomHandler(for: originalEpisode.episode.media)
    }

    Task { try await playManager.load(originalEpisode) }

    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitForQueue([originalEpisode])
    try await PlayHelpers.waitForItemQueue([incomingEpisode, originalEpisode])
  }

  @Test("playing while loading retains playing status")
  func playingWhileLoadingRetainsPlayingStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.executeMidLoad(for: podcastEpisode) {
      await playManager.play()
    }
    try await PlayHelpers.load(podcastEpisode)

    try await PlayHelpers.waitForItemQueue([podcastEpisode])
    try await PlayHelpers.waitForObservations()
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("loading episode already loaded does nothing")
  func loadingEpisodeAlreadyLoadedDoesNothing() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    #expect(try await playManager.load(podcastEpisode) == false)
  }

  // MARK: - Playback Controls

  @Test("play and pause functions play and pause playback")
  func playAndPauseFunctionsPlayAndPausePlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

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

    try await PlayHelpers.load(podcastEpisode)

    commandCenter.continuation.yield(.play)
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)

    commandCenter.continuation.yield(.pause)
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)

    commandCenter.continuation.yield(.togglePlayPause)
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)

    commandCenter.continuation.yield(.togglePlayPause)
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)
  }

  @Test("audio session interruption stops and restarts playback")
  func audioSessionInterruptionStopsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
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

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()

    let advancedTime = CMTime.inSeconds(10)
    avQueuePlayer.advanceTime(to: advancedTime)
    try await PlayHelpers.waitFor(advancedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == advancedTime)
  }

  // MARK: - Seeking

  @Test("seeking updates current time")
  func seekingUpdatesCurrentTime() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let duration = CMTime.inSeconds(240)
    episodeAssetLoader.respond(to: podcastEpisode.episode.media) { _ in (true, duration) }
    try await PlayHelpers.load(podcastEpisode)

    let originalTime = CMTime.inSeconds(120)
    await playManager.seek(to: originalTime)
    try await PlayHelpers.waitFor(originalTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == originalTime)
    #expect(PlayHelpers.nowPlayingProgress == originalTime.seconds / duration.seconds)

    let skipAmount = CMTime.inSeconds(30)
    let skipTime = CMTimeAdd(originalTime, skipAmount)
    await playManager.seekForward(skipAmount)
    try await PlayHelpers.waitFor(skipTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == skipTime)
    #expect(PlayHelpers.nowPlayingProgress == skipTime.seconds / duration.seconds)

    let rewindAmount = CMTime.inSeconds(15)
    let rewindTime = CMTimeSubtract(skipTime, rewindAmount)
    await playManager.seekBackward(rewindAmount)
    try await PlayHelpers.waitFor(rewindTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == rewindTime)
    #expect(PlayHelpers.nowPlayingProgress == rewindTime.seconds / duration.seconds)
  }

  @Test("seeking retains playing status")
  func seekingRetainsPlayStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    let seekSemaphore = AsyncSemaphore(value: 0)
    avQueuePlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return true
    }
    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()

    // Seek and episode will return to playing
    await playManager.seek(to: .inSeconds(60))
    try await PlayHelpers.waitFor(.paused)
    seekSemaphore.signal()
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)
  }

  @Test("playing while seeking retains playing status")
  func playingWhileSeekingRetainsPlayStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

    try await PlayHelpers.executeMidSeek {
      try await PlayHelpers.play()
    }

    // Seek and episode will still be playing once the seek is completed
    await playManager.seek(to: .inSeconds(60))
    try await PlayHelpers.waitForPeriodicTimeObserver()
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)
  }

  @Test("pausing while seeking retains pausing status")
  func pausingWhileSeekingRetainsPausingStatus() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)

    try await PlayHelpers.executeMidSeek {
      try await PlayHelpers.pause()
    }

    // Seek and episode will still be playing once the seek is completed
    await playManager.seek(to: .inSeconds(60))
    try await PlayHelpers.waitForPeriodicTimeObserver()
    try await PlayHelpers.waitFor(.paused)
    #expect(PlayHelpers.nowPlayingPlaying == false)
  }

  @Test("playback is paused while seeking")
  func playbackIsPausedWhileSeeking() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()

    // First seek is interrupted so we stay paused
    let seekSemaphore = AsyncSemaphore(value: 0)
    avQueuePlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return false
    }
    await playManager.seek(to: .inSeconds(30))
    try await PlayHelpers.waitForNoPeriodicTimeObserver()
    try await PlayHelpers.waitFor(.paused)
    seekSemaphore.signal()

    try await PlayHelpers.play()

    // Second seek finishes but we stay paused till it does
    avQueuePlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return true
    }
    await playManager.seek(to: .inSeconds(30))
    try await PlayHelpers.waitFor(.paused)
    seekSemaphore.signal()

    // Now seek has finished, we go back to playing
    try await PlayHelpers.waitFor(.playing)
    #expect(PlayHelpers.nowPlayingPlaying == true)
  }

  @Test("time update events are ignored while seeking")
  func timeUpdateEventsAreIgnoredWhileSeeking() async throws {
    let (failedEpisode, successfulEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.load(failedEpisode)
    try await PlayHelpers.waitForPeriodicTimeObserver()

    // After this failed seek, all time advancement is being ignored
    avQueuePlayer.seekHandler = { _ in false }
    let failedSeekTime = CMTime.inSeconds(60)
    await playManager.seek(to: failedSeekTime)
    try await PlayHelpers.waitForNoPeriodicTimeObserver()

    try await PlayHelpers.load(successfulEpisode)
    try await PlayHelpers.waitForPeriodicTimeObserver()

    // While a seek is in progress, we will ignore time advancement until its success
    let seekSemaphore = AsyncSemaphore(value: 0)
    avQueuePlayer.seekHandler = { _ in
      await seekSemaphore.wait()
      return true
    }
    let successfulSeekTime = CMTimeAdd(failedSeekTime, CMTime.inSeconds(30))
    await playManager.seek(to: successfulSeekTime)
    try await PlayHelpers.waitForNoPeriodicTimeObserver()

    // Our seek completes successfully so time advancement observation is back
    seekSemaphore.signal()
    try await PlayHelpers.waitForPeriodicTimeObserver()
    let advancedTime = CMTimeAdd(successfulSeekTime, CMTime.inSeconds(10))
    avQueuePlayer.advanceTime(to: advancedTime)  // Actually Triggers
    try await PlayHelpers.waitFor(advancedTime)
    #expect(PlayHelpers.nowPlayingCurrentTime == advancedTime)
  }

  // MARK: - Queue Management

  @Test("adding an episode to top of queue while playing")
  func addingAnEpisodeToTopOfQueueWhilePlaying() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.load(playingEpisode)
    try await PlayHelpers.queueNext(queuedEpisode)

    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await PlayHelpers.waitForItemQueue([playingEpisode, queuedEpisode])
  }

  @Test("loading an episode with queue already filled")
  func loadingAnEpisodeWithQueueAlreadyFilled() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.load(playingEpisode)

    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await PlayHelpers.waitForItemQueue([playingEpisode, queuedEpisode])
  }

  @Test("top queue item changes while playing")
  func topQueueItemChangesWhilePlaying() async throws {
    let (playingEpisode, queuedEpisode, incomingQueuedEpisode) =
      try await Create.threePodcastEpisodes()

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.load(playingEpisode)
    try await PlayHelpers.queueNext(incomingQueuedEpisode)

    try await PlayHelpers.waitForQueue([incomingQueuedEpisode, queuedEpisode])
    try await PlayHelpers.waitForItemQueue([playingEpisode, incomingQueuedEpisode])
  }

  @Test("top queue item changes while previous is loading")
  func topQueueItemChangesWhilePreviousIsLoading() async throws {
    let (playingEpisode, queuedEpisode, incomingQueuedEpisode) =
      try await Create.threePodcastEpisodes()

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.executeMidLoad(for: queuedEpisode) {
      try await PlayHelpers.queueNext(incomingQueuedEpisode)
    }
    try await PlayHelpers.load(playingEpisode)

    try await PlayHelpers.waitForQueue([incomingQueuedEpisode, queuedEpisode])
    try await PlayHelpers.waitForItemQueue([playingEpisode, incomingQueuedEpisode]
    )
  }

  @Test("loading a new episode puts current episode back in queue")
  func loadingAnEpisodePutsCurrentEpisodeBackInQueue() async throws {
    let (playingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.load(playingEpisode)
    try await PlayHelpers.load(incomingEpisode)

    try await PlayHelpers.waitForQueue([playingEpisode])
    try await PlayHelpers.waitForItemQueue([incomingEpisode, playingEpisode])
  }

  // MARK: - Episode Finishing

  @Test("finishing last episode with nothing queued clears state")
  func finishingLastEpisodeWithNothingQueuedClearsState() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()
    avQueuePlayer.finishEpisode()

    try await PlayHelpers.waitFor(.stopped)
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(PlayHelpers.itemQueueURLs.isEmpty)
    #expect((try await PlayHelpers.queuedEpisodeIDs).isEmpty)
  }

  @Test("finishing last episode will manually load next episode")
  func finishingLastEpisodeWillManuallyLoadNextEpisode() async throws {
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await PlayHelpers.queueNext(queuedEpisode)

    // This ensures the standard queuing of this item into the avPlayer queue fails
    episodeAssetLoader.respond(to: queuedEpisode.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }

    // Will try to load the queued episode but fail
    try await PlayHelpers.load(originalEpisode)
    try await PlayHelpers.waitForResponse(for: queuedEpisode)

    // Now allow the load to succeed next time we try
    episodeAssetLoader.clearCustomHandler(for: queuedEpisode.episode.media)

    // Once episode is finished it will try again to load the queued episode
    try await PlayHelpers.play()
    avQueuePlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForQueue([])
    try await PlayHelpers.waitForItemQueue([queuedEpisode])
  }

  @Test("advancing to next episode updates state")
  func advancingToNextEpisodeUpdatesState() async throws {
    let (originalEpisode, queuedEpisode, incomingEpisode) =
      try await Create.threePodcastEpisodes()

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.queueNext(incomingEpisode)

    try await PlayHelpers.load(originalEpisode)
    try await PlayHelpers.play()
    avQueuePlayer.finishEpisode()

    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForQueue([queuedEpisode])
    try await PlayHelpers.waitForItemQueue([incomingEpisode, queuedEpisode])
  }

  @Test("advancing to mid-progress episode seeks to new time")
  func advancingToMidProgressEpisodeSeeksToNewTime() async throws {
    let originalTime = CMTime.inSeconds(5)
    let queuedTime = CMTime.inSeconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime),
      Create.unsavedEpisode(currentTime: queuedTime)
    )

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.load(originalEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitFor(originalTime)

    avQueuePlayer.finishEpisode()
    try await PlayHelpers.waitFor(queuedTime)
  }

  @Test("advancing to unplayed episode sets time to zero")
  func advancingToUnplayedEpisodeSetsTimeToZero() async throws {
    let originalTime = CMTime.inSeconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime)
    )

    try await PlayHelpers.queueNext(queuedEpisode)
    try await PlayHelpers.load(originalEpisode)
    try await PlayHelpers.play()
    try await PlayHelpers.waitFor(originalTime)

    avQueuePlayer.finishEpisode()
    try await PlayHelpers.waitFor(.zero)
  }

  @Test("episode is marked complete after playing to end")
  func episodeIsMarkedCompleteAfterPlayingToEnd() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await PlayHelpers.load(podcastEpisode)
    try await PlayHelpers.play()

    avQueuePlayer.finishEpisode()

    try await PlayHelpers.waitForCompleted(podcastEpisode)
  }
}
