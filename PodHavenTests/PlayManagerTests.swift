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

  func continuation(for name: Notification.Name) -> AsyncStream<Notification>.Continuation {
    Container.shared.notifier().continuation(for: name)
  }

  init() async throws {
    await playManager.start()
  }

  @Test("simple loading and playing episode")
  func simpleLoadAndPlayEpisode() async throws {
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode()]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

    try await playManager.load(podcastEpisode)
    let onDeck: OnDeck = try await TestHelpers.waitForValue { await playState.onDeck }
    #expect(avQueuePlayer.items().map(\.assetURL) == [podcastEpisode.episode.media.rawValue])
    #expect(onDeck == podcastEpisode)
    #expect(nowPlayingInfo?[MPMediaItemPropertyTitle] as! String == podcastEpisode.episode.title)

    await playManager.play()
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)
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
    try await playManager.load(podcastEpisode)

    await playManager.play()
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)

    commandCenter.continuation.yield(.pause)
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .paused)

    commandCenter.continuation.yield(.play)
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)

    commandCenter.continuation.yield(.togglePlayPause)
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .paused)

    commandCenter.continuation.yield(.togglePlayPause)
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)
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
    try await playManager.load(podcastEpisode)

    await playManager.play()
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)

    let interruptionContinuation = continuation(for: AVAudioSession.interruptionNotification)

    // Interruption began: pause playback
    interruptionContinuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
      )
    )
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .paused)

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
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)
  }

  @Test("seeking retains original play status")
  func seekingRetainsOriginalPlayStatus() async throws {
    // In progress means seek will happen upon loading
    let inProgressEpisode = try TestHelpers.unsavedEpisode(currentTime: CMTime.inSeconds(120))
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [inProgressEpisode]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

    // Seek will happen because episode has currentTime
    try await playManager.load(podcastEpisode)
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .active)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Pause episode
    await playManager.pause()
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Seek and episode remains paused
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Play episode
    await playManager.play()
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)

    // Seek and episode remains playing
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(50))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }
}
