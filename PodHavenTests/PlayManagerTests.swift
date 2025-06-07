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

  @Test("simple loading, playing, and pausing episode")
  func simpleLoadPlayAndPauseEpisode() async throws {
    let podcastEpisode = try await TestHelpers.podcastEpisode()

    let onDeck = try await load(podcastEpisode)
    #expect(playState.status == .paused)
    #expect(itemQueueURLs == episodeMediaURLs([podcastEpisode]))
    #expect(onDeck == podcastEpisode)
    #expect(nowPlayingTitle == podcastEpisode.episode.title)

    await playManager.play()
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)

    await playManager.pause()
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)
  }

  @Test("loading an episode updates its duration value")
  func loadingEpisodeUpdatesDuration() async throws {
    let originalDuration = CMTime.inSeconds(10)
    let podcastEpisode = try await TestHelpers.podcastEpisode(
      TestHelpers.unsavedEpisode(duration: originalDuration)
    )

    let correctDuration = CMTime.inSeconds(999)
    episodeAssetLoader.respond(to: podcastEpisode.episode.media) { mediaURL in
      (true, correctDuration)
    }

    let onDeck = try await load(podcastEpisode)
    #expect(onDeck.duration == correctDuration)

    let updatedPodcastEpisode = try await repo.episode(podcastEpisode.id)
    #expect(updatedPodcastEpisode?.episode.duration == correctDuration)
  }

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {
    let podcastEpisode = try await TestHelpers.podcastEpisode()

    try await load(podcastEpisode)
    try await play()

    commandCenter.continuation.yield(.pause)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    commandCenter.continuation.yield(.play)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)

    commandCenter.continuation.yield(.togglePlayPause)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    commandCenter.continuation.yield(.togglePlayPause)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }

  @Test("audio session interruption stops and restarts playback")
  func audioSessionInterruptionStopsPlayback() async throws {
    let podcastEpisode = try await TestHelpers.podcastEpisode()

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
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Interruption ended: resume playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
          AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume
            .rawValue,
        ]
      )
    )
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }

  @Test("seeking retains original play status")
  func seekingRetainsOriginalPlayStatus() async throws {
    // In progress means seek will happen upon loading
    let podcastEpisode = try await TestHelpers.podcastEpisode(
      TestHelpers.unsavedEpisode(currentTime: .inSeconds(120))
    )

    // Seek will happen because episode has currentTime
    try await load(podcastEpisode)
    #expect(playState.currentTime == .inSeconds(120))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Pause episode
    try await pause()

    // Seek and episode remains paused
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == .inSeconds(150))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Play episode
    try await play()

    // Seek and episode remains playing
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.currentTime == .inSeconds(180))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }

  @Test("adding an episode to top of queue while playing")
  func addingAnEpisodeToTopOfQueueWhilePlaying() async throws {
    let (playingEpisode, queuedEpisode) = try await TestHelpers.twoPodcastEpisodes()

    try await load(playingEpisode)
    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([playingEpisode, queuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([queuedEpisode]))
  }

  @Test("loading an episode with queue already filled")
  func loadingAnEpisodeWithQueueAlreadyFilled() async throws {
    let (playingEpisode, queuedEpisode) = try await TestHelpers.twoPodcastEpisodes()

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
      try await TestHelpers.threePodcastEpisodes()

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
    let (playingEpisode, incomingEpisode) = try await TestHelpers.twoPodcastEpisodes()

    try await load(playingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    try await load(incomingEpisode)
    try await Task.sleep(for: .milliseconds(100))

    #expect(itemQueueURLs == episodeMediaURLs([incomingEpisode, playingEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([playingEpisode]))
  }

  @Test("loading an episode fails with none playing right now")
  func loadingAnEpisodeFailsWithNonePlayingRightNow() async throws {
    let episodeToLoad = try await TestHelpers.podcastEpisode()

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
  }

  @Test("loading an episode fails with one playing right now")
  func loadingAnEpisodeFailsWithOnePlayingRightNow() async throws {
    let (playingEpisode, episodeToLoad) = try await TestHelpers.twoPodcastEpisodes()

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

  @Test("current item becoming nil clears deck")
  func currentItemBecomingNilClearsDeck() async throws {
    let podcastEpisode = try await TestHelpers.podcastEpisode()

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

  @Test("current item advancing to next episode")
  func currentItemAdvancingToNextEpisode() async throws {
    let (originalEpisode, queuedEpisode, incomingEpisode) =
      try await TestHelpers.threePodcastEpisodes()

    try await queue.unshift(queuedEpisode.id)
    try await queue.unshift(incomingEpisode.id)

    try await load(originalEpisode)
    try await play()
    try await Task.sleep(for: .milliseconds(200))

    avQueuePlayer.simulateFinishingEpisode()
    try await Task.sleep(for: .milliseconds(200))

    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
    #expect(playState.onDeck! == incomingEpisode)
    #expect(nowPlayingTitle == incomingEpisode.episode.title)
    #expect(itemQueueURLs == episodeMediaURLs([incomingEpisode, queuedEpisode]))
    let queued = episodeStrings(try await queuedPodcastEpisodes)
    #expect(queued == episodeStrings([queuedEpisode]))
  }

  @Test("periodicTimeObserver events are ignored while seeking")
  func periodicTimeObserverEventsAreIgnoredWhileSeeking() async throws {
    var correctTime = CMTime.inSeconds(30)
    let podcastEpisode = try await TestHelpers.podcastEpisode(
      TestHelpers.unsavedEpisode(currentTime: correctTime)
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

  // MARK: - Helpers

  @discardableResult
  private func load(_ podcastEpisode: PodcastEpisode) async throws -> OnDeck {
    try await playManager.load(podcastEpisode)
    return try await TestHelpers.waitForValue { await playState.onDeck }
  }

  private func play() async throws {
    await playManager.play()
    try await TestHelpers.waitUntil { await playState.status == .playing }
  }

  private func pause() async throws {
    await playManager.pause()
    try await TestHelpers.waitUntil { await playState.status == .paused }
  }

  private var nowPlayingTitle: String {
    nowPlayingInfo![MPMediaItemPropertyTitle] as! String
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
}
