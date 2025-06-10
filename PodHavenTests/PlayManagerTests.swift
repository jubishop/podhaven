// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
@MainActor struct PlayManagerTests {
  @DynamicInjected(\.episodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.images) private var images
  @DynamicInjected(\.mpNowPlayingInfoCenter) private var mpNowPlayingInfoCenter
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @DynamicInjected(\.avQueuePlayer) private var injectedAVQueuePlayer
  @DynamicInjected(\.commandCenter) private var injectedCommandCenter

  var avQueuePlayer: FakeAVQueuePlayer { injectedAVQueuePlayer as! FakeAVQueuePlayer }
  var commandCenter: FakeCommandCenter { injectedCommandCenter as! FakeCommandCenter }
  var nowPlayingInfo: [String: Any?]? { mpNowPlayingInfoCenter.nowPlayingInfo }

  func notificationContinuation(for name: Notification.Name)
    -> AsyncStream<Notification>.Continuation
  {
    Container.shared.notifier().continuation(for: name)
  }

  init() async throws {
    await playManager.start()
  }

  // MARK: - Loading

  @Test("simple loading sets all data")
  func simpleLoadSetsAllData() async throws {
    let podcastEpisode = try await Create.podcastEpisode(Create.unsavedEpisode(image: URL.valid()))

    let onDeck = try await load(podcastEpisode)
    #expect(onDeck == podcastEpisode)
    #expect(itemQueueURLs == episodeMediaURLs([podcastEpisode]))

    #expect(nowPlayingInfo![MPMediaItemPropertyAlbumTitle] as? String == onDeck.podcastTitle)
    let image = try await images.fetchImage(podcastEpisode.podcast.image)
    let artwork = nowPlayingInfo![MPMediaItemPropertyArtwork] as! MPMediaItemArtwork
    let artworkImage = artwork.image(at: image.size)!
    #expect(artworkImage.isVisuallyEqual(to: image))
    #expect(nowPlayingInfo![MPMediaItemPropertyMediaType] as? UInt == MPMediaType.podcast.rawValue)
    #expect(
      nowPlayingInfo![MPMediaItemPropertyPlaybackDuration] as? Double == onDeck.duration.seconds
    )
    #expect(nowPlayingInfo![MPMediaItemPropertyTitle] as? String == onDeck.episodeTitle)
    #expect(nowPlayingInfo![MPNowPlayingInfoCollectionIdentifier] as? String == onDeck.podcastTitle)
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyAssetURL] as? URL == onDeck.media.rawValue)
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyDefaultPlaybackRate] as? Double == 1.0)
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double == 0.0)
    #expect(
      nowPlayingInfo![MPNowPlayingInfoPropertyExternalContentIdentifier] as? String
        == onDeck.guid.rawValue
    )
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyIsLiveStream] as? Bool == false)
    #expect(
      nowPlayingInfo![MPNowPlayingInfoPropertyMediaType] as? UInt
        == MPNowPlayingInfoMediaType.audio.rawValue
    )
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackProgress] as? Double == 0.0)
    #expect(nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0.0)
  }

  @Test("loading an episode seeks to its current time")
  func loadingEpisodeSeeksToCurrentTime() async throws {
    let currentTime: CMTime = .inSeconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: currentTime)
    )

    try await load(podcastEpisode)
    try await waitFor(currentTime)
    #expect(nowPlayingCurrentTime == currentTime)
  }

  @Test("loading an episode updates its duration value")
  func loadingEpisodeUpdatesDuration() async throws {
    let originalDuration = CMTime.inSeconds(10)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: originalDuration)
    )

    let correctDuration = CMTime.inSeconds(20)
    episodeAssetLoader.respond(to: podcastEpisode.episode.media) { _ in (true, correctDuration) }

    let onDeck = try await load(podcastEpisode)
    #expect(onDeck.duration == correctDuration)

    let updatedPodcastEpisode = try await repo.episode(podcastEpisode.id)
    #expect(updatedPodcastEpisode?.episode.duration == correctDuration)
  }

  // MARK: - Playback Controls

  @Test("play and pause functions play and pause playback")
  func playAndPauseFunctionsPlayAndPausePlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await load(podcastEpisode)

    await playManager.play()
    try await waitFor(.playing)
    #expect(nowPlayingPlaying == true)

    await playManager.pause()
    try await waitFor(.paused)
    #expect(nowPlayingPlaying == false)
  }

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await load(podcastEpisode)

    commandCenter.continuation.yield(.play)
    try await waitFor(.playing)

    commandCenter.continuation.yield(.pause)
    try await waitFor(.paused)

    commandCenter.continuation.yield(.togglePlayPause)
    try await waitFor(.playing)

    commandCenter.continuation.yield(.togglePlayPause)
    try await waitFor(.paused)
  }

  @Test("audio session interruption stops and restarts playback")
  func audioSessionInterruptionStopsPlayback() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await load(podcastEpisode)
    try await play()

    let interruptionContinuation = notificationContinuation(
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
    try await waitFor(.paused)

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
    try await waitFor(.playing)
  }

  // MARK: - Seeking
  // TODO: Update all tests below here
  @Test("seeking works and retains play status")
  func seekingRetainsOriginalPlayStatus() async throws {
    // In progress means seek will happen upon loading
    let duration = CMTime.inSeconds(240)
    let skipAmount = CMTime.inSeconds(15)
    var currentTime = CMTime.inSeconds(120)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(duration: duration, currentTime: currentTime)
    )

    // Seek will happen because episode has currentTime
    episodeAssetLoader.respond(to: podcastEpisode.episode.media) { mediaURL in
      (true, duration)
    }
    let onDeck = try await load(podcastEpisode)
    #expect(onDeck.duration == duration)
    #expect(playState.currentTime == currentTime)
    #expect(nowPlayingCurrentTime == currentTime)
    #expect(nowPlayingProgress == currentTime.seconds / duration.seconds)
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Pause episode
    try await pause()

    // Seek and episode remains paused
    currentTime += skipAmount
    await playManager.seekForward(skipAmount)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == currentTime)
    #expect(nowPlayingCurrentTime == currentTime)
    #expect(nowPlayingProgress == currentTime.seconds / duration.seconds)
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Play episode
    try await play()

    // Seek and episode remains playing
    currentTime += skipAmount
    await playManager.seekForward(skipAmount)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == currentTime)
    #expect(nowPlayingCurrentTime == currentTime)
    #expect(nowPlayingProgress == currentTime.seconds / duration.seconds)
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }

  @Test("playback is paused while seeking")
  func playbackIsPausedWhileSeeking() async throws {
    let podcastEpisode = try await Create.podcastEpisode()
    try await load(podcastEpisode)
    try await play()

    // First seek is interrupted so we stay paused
    avQueuePlayer.seekHandler = { _ in false }
    await playManager.seek(to: .inSeconds(30))
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)

    // Second seek finishes but slowly
    avQueuePlayer.seekHandler = { _ in
      try? await Task.sleep(for: .milliseconds(100))
      return true
    }
    await playManager.seek(to: .inSeconds(30))
    #expect(playState.status == .paused)  // Still paused since seek has not completed

    // Now seek has finished, we go back to playing
    try await Task.sleep(for: .milliseconds(200))
    try await Wait.until(
      { await playState.status == .playing },
      { "Status is: \(await playState.status)" }
    )
    #expect(playState.currentTime == .inSeconds(30))
  }

  @Test("periodicTimeObserver events are ignored while seeking")
  func periodicTimeObserverEventsAreIgnoredWhileSeeking() async throws {
    var correctTime = CMTime.inSeconds(30)
    let podcastEpisode = try await Create.podcastEpisode(
      Create.unsavedEpisode(currentTime: correctTime)
    )
    try await load(podcastEpisode)
    #expect(playState.currentTime == correctTime)

    // After this seek, all time advancement is being ignored
    avQueuePlayer.seekHandler = { _ in false }
    correctTime += .inSeconds(10)
    await playManager.seek(to: correctTime)  // Time observation turned off after this
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == correctTime)

    // Since no seek was successful we are ignoring these right now
    avQueuePlayer.simulateTimeAdvancement(to: .inSeconds(999))  // Ignored
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == correctTime)  // Still what it was at seek

    // Since a seek is in progress, we will ignore time advancement until its success
    avQueuePlayer.seekHandler = { _ in
      try! await Task.sleep(for: .milliseconds(200))
      return true
    }
    correctTime += .inSeconds(10)
    await playManager.seek(to: correctTime)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == correctTime)
    avQueuePlayer.simulateTimeAdvancement(to: .inSeconds(999))  // Ignored
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == correctTime)  // Still what it was at seek

    // After this, our seek completed successfully so time advancement observation is back
    try await Task.sleep(for: .milliseconds(100))
    correctTime += .inSeconds(10)
    avQueuePlayer.simulateTimeAdvancement(to: correctTime)  // Actually Triggers
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == correctTime)
  }

  // MARK: - Queue Management

  @Test("adding an episode to top of queue while playing")
  func addingAnEpisodeToTopOfQueueWhilePlaying() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await load(playingEpisode)
    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([playingEpisode, queuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([queuedEpisode]))
  }

  @Test("loading an episode with queue already filled")
  func loadingAnEpisodeWithQueueAlreadyFilled() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))
    try await load(playingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([playingEpisode, queuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([queuedEpisode]))
  }

  @Test("top queue item changes while playing")
  func topQueueItemChangesWhilePlaying() async throws {
    let (playingEpisode, queuedEpisode, incomingQueuedEpisode) =
      try await Create.threePodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))
    try await load(playingEpisode)

    try await queue.unshift(incomingQueuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([playingEpisode, incomingQueuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([incomingQueuedEpisode, queuedEpisode]))
  }

  @Test("loading an episode puts current episode back in queue")
  func loadingAnEpisodePutsCurrentEpisodeBackInQueue() async throws {
    let (playingEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()

    try await load(playingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    try await load(incomingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([incomingEpisode, playingEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([playingEpisode]))
  }

  // MARK: - Loading

  @Test("loading an episode fails with none playing right now")
  func loadingAnEpisodeFailsWithNonePlayingRightNow() async throws {
    let episodeToLoad = try await Create.podcastEpisode()

    episodeAssetLoader.respond(to: episodeToLoad.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }
    await #expect(throws: (any Error).self) {
      try await load(episodeToLoad)
    }
    try await Task.sleep(for: .milliseconds(200))
    #expect(playState.status == .stopped)
    #expect(avQueuePlayer.timeControlStatus == .paused)
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(itemQueueURLs.isEmpty)
  }

  @Test("loading an episode fails with one playing right now")
  func loadingAnEpisodeFailsWithOnePlayingRightNow() async throws {
    let (playingEpisode, episodeToLoad) = try await Create.twoPodcastEpisodes()

    try await load(playingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    episodeAssetLoader.respond(to: episodeToLoad.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }
    await #expect(throws: (any Error).self) {
      try await load(episodeToLoad)
    }
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .stopped)
    #expect(avQueuePlayer.timeControlStatus == .paused)
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(itemQueueURLs.isEmpty)
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([episodeToLoad, playingEpisode]))
  }

  @Test("playing while loading episodes leaves status playing, not paused")
  func playingWhileLoadingEpisodesLeavesStatusPlayingNotPaused() async throws {
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    // While these load slowly: the user will click play
    episodeAssetLoader.setDefaultResponse { _ in
      try await Task.sleep(for: .milliseconds(100))
      return (true, .inSeconds(30))
    }
    try await queueNext(queuedEpisode)
    Task { try await load(playingEpisode) }
    try await Wait.until(
      { await playState.onDeck?.episodeTitle == playingEpisode.episode.title },
      { "OnDeck is: \(String(describing: await playState.onDeck))" }
    )
    try await play()  // Play before our queued episode finishes loading

    try await Wait.until {
      let mediaURLs = await episodeMediaURLs([playingEpisode, queuedEpisode])
      return await itemQueueURLs == mediaURLs
    }
    try await Task.sleep(for: .milliseconds(100))
    try await Wait.until(
      { await playState.status == .playing },
      { "Status is: \(await playState.status)" }
    )
  }

  // MARK: - Episode Finishing

  @Test("current item becoming nil clears deck")
  func currentItemBecomingNilClearsDeck() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await load(podcastEpisode)
    try await play()
    avQueuePlayer.simulateFinishingEpisode()
    try await Task.sleep(for: .milliseconds(100))

    #expect(playState.status == .stopped)
    #expect(avQueuePlayer.timeControlStatus == .paused)
    #expect(playState.onDeck == nil)
    #expect(nowPlayingInfo == nil)
    #expect(itemQueueURLs.isEmpty)
    #expect((try await queuedPodcastEpisodes).isEmpty)
  }

  @Test("current item becoming nil with existing next episode loads next episode")
  func currentItemBecomingNilWithExistingNextEpisodeLoadsNextEpisode() async throws {
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    episodeAssetLoader.respond(to: queuedEpisode.episode.media) { mediaURL in
      throw TestError.assetLoadFailure(mediaURL)
    }
    try await queue.unshift(queuedEpisode.id)

    try await load(originalEpisode)
    try await play()
    try await Wait.until(
      { await responseCount(for: queuedEpisode.episode.media) == 1 },
      { "responseCount remains: \(await responseCount(for: queuedEpisode.episode.media))" }
    )

    episodeAssetLoader.clearCustomHandler(for: queuedEpisode.episode.media)
    avQueuePlayer.simulateFinishingEpisode()
    try await Wait.until(
      { await playState.onDeck?.episodeTitle == queuedEpisode.episode.title },
      { "OnDeck is: \(String(describing: await playState.onDeck))" }
    )
    try await Wait.until(
      { await playState.status == .playing },
      { "Status is: \(await playState.status)" }
    )
    #expect(avQueuePlayer.timeControlStatus == .playing)
    #expect(itemQueueURLs == episodeMediaURLs([queuedEpisode]))
  }

  @Test("current item advancing to next episode")
  func currentItemAdvancingToNextEpisode() async throws {
    let (originalEpisode, queuedEpisode, incomingEpisode) =
      try await Create.threePodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await queue.unshift(incomingEpisode.id)

    try await load(originalEpisode)
    try await play()
    try await Task.sleep(for: .milliseconds(100))

    avQueuePlayer.simulateFinishingEpisode()
    try await Task.sleep(for: .milliseconds(100))

    try await Wait.until(
      {
        let title = incomingEpisode.episode.title
        let onDeckTitle = await playState.onDeck?.episodeTitle
        return title == onDeckTitle
      },
      {
        """
        Expected: \(incomingEpisode.episode.title), \
        Got: \(String(describing: await playState.onDeck?.episodeTitle))
        """
      }
    )
    try await Wait.until(
      {
        let status = await playState.status
        let timeControlStatus = await avQueuePlayer.timeControlStatus
        return status == .playing && timeControlStatus == .playing
      },
      {
        """
        Status: \(await playState.status), \
        TimeControl: \(await avQueuePlayer.timeControlStatus)
        """
      }
    )
    #expect(playState.onDeck! == incomingEpisode)
    #expect(itemQueueURLs == episodeMediaURLs([incomingEpisode, queuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([queuedEpisode]))
  }

  @Test("new currentItem with currentTime pauses until after seek and then sets currentTime")
  func advancingToNextEpisodePausesUntilAfterSeekAndThenSetsCurrentTime() async throws {
    let originalTime = CMTime.inSeconds(5)
    let queuedTime = CMTime.inSeconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime),
      Create.unsavedEpisode(currentTime: queuedTime)
    )

    try await queueNext(queuedEpisode)
    try await load(originalEpisode)
    try await play()
    try await Wait.until(
      { await playState.currentTime == originalTime },
      { "CurrentTime is: \(await playState.currentTime), Expected: \(originalTime)" }
    )
    try await Wait.until {
      let mediaURLs = await episodeMediaURLs([originalEpisode, queuedEpisode])
      return await itemQueueURLs == mediaURLs
    }

    avQueuePlayer.seekHandler = { _ in
      try? await Task.sleep(for: .milliseconds(250))
      return true
    }

    avQueuePlayer.simulateFinishingEpisode()
    try await Wait.until(
      { await playState.status == .paused },
      { "Status is: \(await playState.status)" }
    )

    try await Wait.until(
      { await playState.status == .playing },
      { "Status is: \(await playState.status)" }
    )
    try await Wait.until(
      { await playState.currentTime == queuedTime },
      { "CurrentTime is: \(await playState.currentTime), Expected: \(queuedTime)" }
    )
  }

  @Test("new currentItem with no currentTime sets currentTime to zero")
  func newCurrentItemWithNoCurrentTimeSetsCurrentTimeToZero() async throws {
    let originalTime = CMTime.inSeconds(10)
    let (originalEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes(
      Create.unsavedEpisode(currentTime: originalTime)
    )

    try await queue.unshift(queuedEpisode.id)
    try await load(originalEpisode)
    try await play()
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == originalTime)

    avQueuePlayer.simulateFinishingEpisode()
    try await Wait.until(
      { await playState.currentTime == .zero },
      { "CurrentTime is: \(await playState.currentTime), Expected: .zero" }
    )
  }

  @Test("episode is marked complete after playing to end")
  func episodeIsMarkedCompleteAfterPlayingToEnd() async throws {
    let podcastEpisode = try await Create.podcastEpisode()

    try await load(podcastEpisode)
    try await play()

    avQueuePlayer.simulateFinishingEpisode()
    try await Task.sleep(for: .milliseconds(100))
    let fetchedPodcastEpisode = try await repo.episode(podcastEpisode.id)
    #expect(fetchedPodcastEpisode!.episode.completed)
  }

  // MARK: - Action Helpers

  @discardableResult
  private func load(_ podcastEpisode: PodcastEpisode) async throws -> OnDeck {
    try await playManager.load(podcastEpisode)
    return try await Wait.forValue { await playState.onDeck }
  }

  private func waitFor(_ status: PlayState.Status) async throws {
    try await Wait.until(
      { await playState.status == status },
      {
        """
        Status is: \(await playState.status), \
        Expected: \(status)
        """
      }
    )
  }

  private func waitFor(_ time: CMTime) async throws {
    try await Wait.until(
      { await playState.currentTime == time },
      {
        """
        Current time is: \(await playState.currentTime), \
        Expected: \(time)
        """
      }
    )
  }

  private func queueNext(_ podcastEpisode: PodcastEpisode) async throws {
    try await queue.unshift(podcastEpisode.id)
    try await Wait.until(
      { try await queue.nextEpisode?.id == podcastEpisode.id },
      {
        """
        Next episode ID: \(String(describing: try await queue.nextEpisode?.id)), \
        Expected: \(podcastEpisode.id)
        """
      }
    )
  }

  private func play() async throws {
    await playManager.play()
    try await waitFor(.playing)
  }

  private func pause() async throws {
    await playManager.pause()
    try await waitFor(.paused)
  }

  // MARK: - Comparison Helpers

  private var nowPlayingPlaying: Bool {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1.0
  }

  private var nowPlayingCurrentTime: CMTime {
    CMTime.inSeconds(nowPlayingInfo![MPNowPlayingInfoPropertyElapsedPlaybackTime] as! Double)
  }

  private var nowPlayingProgress: Double {
    nowPlayingInfo![MPNowPlayingInfoPropertyPlaybackProgress] as! Double
  }

  private var itemQueueURLs: [MediaURL] {
    avQueuePlayer.queued.map(\.assetURL)
  }

  private var queuedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      try await repo.db.read { db in
        try Episode
          .all()
          .queued()
          .order(\.queueOrder.asc)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchAll(db)
      }
    }
  }

  private func episodeStrings(_ podcastEpisodes: [PodcastEpisode]) -> [String] {
    podcastEpisodes.map(\.toString)
  }

  private func episodeMediaURLs(_ podcastEpisodes: [PodcastEpisode]) -> [MediaURL] {
    podcastEpisodes.map(\.episode.media)
  }

  func responseCount(for mediaURL: MediaURL) -> Int {
    episodeAssetLoader.responseCounts[mediaURL, default: 0]
  }
}
