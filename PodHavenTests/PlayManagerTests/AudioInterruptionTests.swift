// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Semaphore
import Testing

@testable import PodHaven

@Suite("of audio interruption tests", .container)
@MainActor struct AudioInterruptionTests {
  enum PlayingInterruption: CaseIterable {
    case reported, playerPausedFirst, reportedTwice, itemFailedDuring
  }
  enum DeclinedResume: CaseIterable {
    case pausedBefore, pausedDuring, toggledDuring, earlierEndDeclined
  }
  enum PendingPlayback: CaseIterable { case selection, advanceResolving, advanceLoading }

  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.notifier) private var notifier
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }

  init() async throws {
    stateManager.start()
    PlayHelpers.setupCommandHandling()
  }

  @Test(
    "an interruption that began during playback resumes it",
    arguments: PlayingInterruption.allCases
  )
  func interruptionDuringPlaybackResumesIt(interruption: PlayingInterruption) async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    switch interruption {
    case .reported:
      try await beginInterruption()
    case .playerPausedFirst:
      // AVPlayer pauses itself for an interruption, possibly before its notification arrives.
      avPlayer.pause()
      try await PlayHelpers.waitFor(.paused)
      try await beginInterruption()
    case .reportedTwice:
      try await beginInterruption()
      try await beginInterruption()
    case .itemFailedDuring:
      try await beginInterruption()
      let failedItem = try #require(avPlayer.current as? FakeAVPlayerItem)
      failedItem.setStatus(.failed)
      try await Wait.until(
        { @MainActor in
          guard let item = avPlayer.current as? FakeAVPlayerItem else { return false }
          return item !== failedItem
        },
        { "Expected recovery to reload the failed item" }
      )
      try await PlayHelpers.waitForOnDeck(podcastEpisode)
    }
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    endInterruption(shouldResume: true)
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )
  }

  @Test(
    "an interruption ending with shouldResume leaves declined playback paused",
    arguments: DeclinedResume.allCases
  )
  func interruptionLeavesDeclinedPlaybackPaused(declined: DeclinedResume) async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    switch declined {
    case .pausedBefore:
      try await PlayHelpers.pause()
      try await beginInterruption()
    case .pausedDuring:
      try await beginInterruption()
      await playManager.pause()
    case .toggledDuring:
      try await beginInterruption()
      await playManager.toggle()
      await playManager.toggle()
    case .earlierEndDeclined:
      try await beginInterruption()
      endInterruption(shouldResume: false)
      try await beginInterruption()
    }
    let playCount = avPlayer.playCallCount

    endInterruption(shouldResume: true)
    // Notifications are handled in order, so a later interruption's pause shows
    // the end was fully handled.
    try await beginInterruption()

    #expect(avPlayer.playCallCount == playCount)
  }

  @Test(
    "an interruption that began before pending playback started resumes it",
    arguments: PendingPlayback.allCases
  )
  func interruptionDuringPendingPlaybackResumesIt(pending: PendingPlayback) async throws {
    await playManager.start()
    let (currentEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    let fakeQueue = try #require(queue as? FakeQueue)
    let phaseStarted = AsyncSemaphore(value: 0)
    let finishPhase = AsyncSemaphore(value: 0)
    defer { finishPhase.signal() }

    switch pending {
    case .selection:
      try await playManager.load(currentEpisode)
    case .advanceResolving, .advanceLoading:
      try await queue.unshift(incomingEpisode.id)
      try await playManager.load(currentEpisode)
      try await PlayHelpers.play()
    }
    switch pending {
    case .advanceResolving:
      fakeQueue.beforeNextEpisode {
        phaseStarted.signal()
        await finishPhase.wait()
      }
    case .selection, .advanceLoading:
      await episodeAssetLoader.respond(to: incomingEpisode.episode.mediaURL) { _ in
        phaseStarted.signal()
        await finishPhase.wait()
        return (true, .seconds(60))
      }
    }
    let selection: Task<PlayManager.SelectionResult, any Error>?
    switch pending {
    case .selection:
      selection = Task { try await playManager.play(incomingEpisode) }
    case .advanceResolving, .advanceLoading:
      selection = nil
      avPlayer.finishEpisode()
    }
    defer { selection?.cancel() }
    await phaseStarted.wait()

    try await beginInterruption()
    finishPhase.signal()
    if let selection { #expect(try await selection.value == .superseded) }
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.paused)

    endInterruption(shouldResume: true)
    try await PlayHelpers.waitFor(.playing)
  }

  @Test("interruption notifications missing their type or options are ignored")
  func interruptionNotificationsMissingKeysAreIgnored() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    try await beginInterruption()
    try await PlayHelpers.waitFor(.paused)
    let playCount = avPlayer.playCallCount

    let continuation = notifier.continuation(for: AVAudioSession.interruptionNotification)
    continuation.yield(Notification(name: AVAudioSession.interruptionNotification))
    continuation.yield(
      Notification(
        name: AVAudioSession.interruptionNotification,
        userInfo: [
          AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
        ]
      )
    )
    // Notifications are handled in order, so a later interruption's pause shows
    // the malformed ones were handled.
    try await beginInterruption()
    #expect(avPlayer.playCallCount == playCount)

    endInterruption(shouldResume: true)
    try await PlayHelpers.waitFor(.playing)
  }

  // MARK: - Helpers

  private func beginInterruption() async throws {
    let pauseCount = avPlayer.pauseCallCount
    notifier.continuation(for: AVAudioSession.interruptionNotification)
      .yield(
        Notification(
          name: AVAudioSession.interruptionNotification,
          userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
          ]
        )
      )
    try await Wait.until(
      { @MainActor in avPlayer.pauseCallCount > pauseCount },
      { "Expected the interruption to pause playback" }
    )
  }

  private func endInterruption(shouldResume: Bool) {
    let options: AVAudioSession.InterruptionOptions = shouldResume ? .shouldResume : []
    notifier.continuation(for: AVAudioSession.interruptionNotification)
      .yield(
        Notification(
          name: AVAudioSession.interruptionNotification,
          userInfo: [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: options.rawValue,
          ]
        )
      )
  }
}
