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
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode()]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

    let onDeck = try await load(podcastEpisode)
    #expect(playState.status == .active)
    #expect(queueURLs == episodeMediaURLs([podcastEpisode]))
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

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode()]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

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
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode()]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

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
    let inProgressEpisode = try TestHelpers.unsavedEpisode(currentTime: .inSeconds(120))
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [inProgressEpisode]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

    // Seek will happen because episode has currentTime
    try await load(podcastEpisode)
    #expect(playState.currentTime == .inSeconds(120))
    #expect(playState.status == .active)
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
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode(), TestHelpers.unsavedEpisode()]
    )
    let playingEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[0]
    )
    let queuedEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[1]
    )

    try await load(playingEpisode)
    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(queueURLs == episodeMediaURLs([playingEpisode, queuedEpisode]))
  }

  @Test("loading an episode with queue already filled")
  func loadingAnEpisodeWithQueueAlreadyFilled() async throws {
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode(), TestHelpers.unsavedEpisode()]
    )
    let playingEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[0]
    )
    let queuedEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[1]
    )

    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))
    try await load(playingEpisode)

    #expect(queueURLs == episodeMediaURLs([playingEpisode, queuedEpisode]))
  }

  @Test("top queue item changes while playing")
  func topQueueItemChangesWhilePlaying() async throws {
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [
        TestHelpers.unsavedEpisode(), TestHelpers.unsavedEpisode(), TestHelpers.unsavedEpisode(),
      ]
    )
    let playingEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[0]
    )
    let queuedEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[1]
    )
    let incomingQueuedEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes[2]
    )

    try await queue.unshift(queuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))
    try await load(playingEpisode)

    try await queue.unshift(incomingQueuedEpisode.id)
    try await Task.sleep(for: .milliseconds(100))

    #expect(queueURLs == episodeMediaURLs([playingEpisode, incomingQueuedEpisode]))
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

  private var queueURLs: [URL] {
    avQueuePlayer.items().map(\.assetURL)
  }

  private func episodeMediaURLs(_ podcastEpisodes: [PodcastEpisode]) -> [URL] {
    podcastEpisodes.map((\.episode.media.rawValue))
  }
}
