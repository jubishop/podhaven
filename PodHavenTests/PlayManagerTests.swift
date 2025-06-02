// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of PlayManager tests", .container)
@MainActor struct PlayManagerTests {
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @DynamicInjected(\.avQueuePlayer) private var injectedAVQueuePlayer
  @DynamicInjected(\.commandCenter) private var injectedCommandCenter

  var avQueuePlayer: FakeAVQueuePlayer { injectedAVQueuePlayer as! FakeAVQueuePlayer }
  var commandCenter: FakeCommandCenter { injectedCommandCenter as! FakeCommandCenter }

  init() async throws {
    await playManager.start()
  }

  @Test("simple loading episode")
  func simpleLoadEpisode() async throws {
    let podcastSeries = try await repo.insertSeries(
      TestHelpers.unsavedPodcast(),
      unsavedEpisodes: [TestHelpers.unsavedEpisode()]
    )
    let podcastEpisode = PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: podcastSeries.episodes.first!
    )

    try await playManager.load(podcastEpisode)
    #expect(avQueuePlayer.items().map(\.assetURL) == [podcastEpisode.episode.media.rawValue])

    // let continuation = try await Notifier.get(AVAudioSession.interruptionNotification)
    // continuation.yield(Notification(name: .init("Test")))

    //commandCenter.continuation.yield(.play)
    //commandCenter.continuation.yield(.pause)
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

    // Seek will happen because episode has begun,
    // but status only goes to active and episode remains paused
    try await playManager.load(podcastEpisode)
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .active)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Pause episode
    await playManager.pause()
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Seek and status and episode remains paused
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .paused)
    #expect(avQueuePlayer.timeControlStatus == .paused)

    // Play episode
    await playManager.play()
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)

    // Seek and episode remains playing
    await playManager.seekForward(CMTime.inSeconds(30))
    try await Task.sleep(for: .milliseconds(100))
    #expect(playState.status == .playing)
    #expect(avQueuePlayer.timeControlStatus == .playing)
  }
}
