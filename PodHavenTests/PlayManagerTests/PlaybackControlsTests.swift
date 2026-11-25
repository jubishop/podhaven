// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import MediaPlayer
import Semaphore
import Testing

@testable import PodHaven

@Suite("of Playback controls tests", .container)
@MainActor struct PlaybackControlsTests {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.fakeEpisodeAssetLoader) private var episodeAssetLoader
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager

  private var avPlayer: FakeAVPlayer {
    Container.shared.avPlayer() as! FakeAVPlayer
  }
  private var mpRemoteCommandCenter: FakeMPRemoteCommandCenter {
    Container.shared.mpRemoteCommandCenter() as! FakeMPRemoteCommandCenter
  }
  private var commandCenterContinuation: AsyncStream<CommandCenter.Command>.Continuation {
    Container.shared.commandCenterStream().continuation
  }
  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  init() async throws {
    stateManager.start()
    cacheManager.start()
    PlayHelpers.setupCommandHandling()
  }

  // MARK: - Playback Controls

  @Test("play and pause functions play and pause playback")
  func playAndPauseFunctionsPlayAndPausePlayback() async throws {

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    await playManager.play()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )
  }

  @Test("command center stops and starts playback")
  func commandCenterStopsAndStartsPlayback() async throws {

    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)

    mpRemoteCommandCenter.firePlay()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    mpRemoteCommandCenter.firePause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    mpRemoteCommandCenter.fireTogglePlayPause()
    try await PlayHelpers.waitFor(.playing)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 1.0
    )

    mpRemoteCommandCenter.fireTogglePlayPause()
    try await PlayHelpers.waitFor(.paused)
    try await PlayHelpers.waitForNowPlayingInfo(
      key: MPNowPlayingInfoPropertyPlaybackRate,
      value: 0.0
    )

    mpRemoteCommandCenter.fireSkipForward(TimeInterval.seconds(2))
    try await PlayHelpers.waitFor(CMTime.seconds(2))

    mpRemoteCommandCenter.fireSkipBackward(TimeInterval.seconds(1))
    try await PlayHelpers.waitFor(CMTime.seconds(1))

    mpRemoteCommandCenter.fireSeek(to: TimeInterval.seconds(5))
    try await PlayHelpers.waitFor(CMTime.seconds(5))
  }

  @Test("stale seek commands are ignored after episode finish")
  func staleSeekCommandsAreIgnoredAfterEpisodeFinish() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish the current episode and auto-advance to the queued one.
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)

    // Queue a stale scrub from the finished episode, then a playback-rate
    // marker. Once the rate changes, the stale scrub has already been
    // processed.
    commandCenterContinuation.yield(
      .playbackPosition(
        TimeInterval.seconds(5),
        sourceEpisodeID: playingEpisode.id,
        eventTimestamp: Date().timeIntervalSinceReferenceDate
      )
    )
    commandCenterContinuation.yield(.changePlaybackRate(1.7))
    try await PlayHelpers.waitForPlayRate(1.7)

    #expect(sharedState.onDeck?.id == queuedEpisode.id)
    #expect(sharedState.onDeck?.currentTime == .zero)
    #expect(await PlayHelpers.nowPlayingCurrentTime == .zero)
  }

  @Test("scrub commands with current episode ID are ignored during suppression window")
  func scrubCommandsWithCurrentEpisodeIDIgnoredDuringSuppression() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish the current episode and auto-advance to the queued one.
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)

    // Simulate what iOS does: deliver a stale scrub with the NEW episode's
    // ID (captured at delivery time after the transition completed).
    commandCenterContinuation.yield(
      .playbackPosition(
        TimeInterval.seconds(500),
        sourceEpisodeID: queuedEpisode.id,
        eventTimestamp: Date().timeIntervalSinceReferenceDate
      )
    )
    commandCenterContinuation.yield(.changePlaybackRate(1.7))
    try await PlayHelpers.waitForPlayRate(1.7)

    #expect(sharedState.onDeck?.id == queuedEpisode.id)
    #expect(sharedState.onDeck?.currentTime == .zero)
    #expect(await PlayHelpers.nowPlayingCurrentTime == .zero)
  }

  @Test("scrub with current episode ID is ignored past the prior suppression window")
  func scrubWithCurrentEpisodeIDIgnoredPastPriorWindow() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish the current episode and auto-advance to the queued one.
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)

    // The tail of a lock-screen drag can land well after the transition — past
    // the window that previously let it through and skipped the freshly loaded
    // episode. Suppression must still be active that far out. Asserting the
    // flag first also settles the suppression task before the scrub below.
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .milliseconds(750))
    #expect(await playManager.ignoreRemoteScrubCommands)

    // A scrub to the new episode's end, carrying its ID, is still dropped.
    commandCenterContinuation.yield(
      .playbackPosition(
        TimeInterval.seconds(500),
        sourceEpisodeID: queuedEpisode.id,
        eventTimestamp: Date().timeIntervalSinceReferenceDate
      )
    )
    commandCenterContinuation.yield(.changePlaybackRate(1.7))
    try await PlayHelpers.waitForPlayRate(1.7)

    #expect(sharedState.onDeck?.id == queuedEpisode.id)
    #expect(sharedState.onDeck?.currentTime == .zero)
    #expect(await PlayHelpers.nowPlayingCurrentTime == .zero)
  }

  @Test("fresh seek commands still work after episode finish")
  func freshSeekCommandsStillWorkAfterEpisodeFinish() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)

    // Advance past the suppression window
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(2))
    try await Wait.until(
      { await playManager.ignoreRemoteScrubCommands == false },
      { "Expected remote scrub suppression to end after time advance" }
    )

    mpRemoteCommandCenter.fireSeek(to: TimeInterval.seconds(10))
    try await PlayHelpers.waitFor(.seconds(10))
  }

  @Test("scrub to a just-started episode's full duration is dropped past the suppression window")
  func scrubToJustStartedEpisodeFullDurationIsDropped() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Finish the current episode and auto-advance to the queued one.
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)

    // Let the blanket time-based suppression lapse so only the position-based
    // guard is left to reject the scrub.
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(2))
    try await Wait.until(
      { await playManager.ignoreRemoteScrubCommands == false },
      { "Expected remote scrub suppression to end after time advance" }
    )

    // The tail of the finished episode's lock-screen drag, redelivered with the
    // new episode's ID and mapped onto its full duration while it sits at 0:00.
    let fullDuration = try #require(sharedState.onDeck?.duration)
    commandCenterContinuation.yield(
      .playbackPosition(
        fullDuration.seconds,
        sourceEpisodeID: queuedEpisode.id,
        eventTimestamp: Date().timeIntervalSinceReferenceDate
      )
    )
    commandCenterContinuation.yield(.changePlaybackRate(1.7))
    try await PlayHelpers.waitForPlayRate(1.7)

    #expect(sharedState.onDeck?.id == queuedEpisode.id)
    #expect(sharedState.onDeck?.currentTime == .zero)
    #expect(await PlayHelpers.nowPlayingCurrentTime == .zero)
  }

  @Test("scrub to the end of a long-playing episode is still applied")
  func scrubToEndIsAppliedAfterPlayingAwhile() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Play to the midpoint — well past the just-started window.
    let fullDuration = try #require(sharedState.onDeck?.duration)
    let midpoint = CMTime.seconds(fullDuration.seconds / 2)
    avPlayer.advanceTime(to: midpoint)
    try await PlayHelpers.waitFor(midpoint)

    // A deliberate scrub to the very end is honored.
    mpRemoteCommandCenter.fireSeek(to: fullDuration.seconds)
    try await PlayHelpers.waitFor(fullDuration)
  }

  @Test("a mid-episode scrub on a just-started episode is still applied")
  func midScrubOnJustStartedEpisodeIsApplied() async throws {
    await playManager.start()
    let (playingEpisode, queuedEpisode) = try await Create.twoPodcastEpisodes()

    try await Container.shared.queue().unshift(queuedEpisode.id)
    try await playManager.load(playingEpisode)
    await playManager.play()
    try await PlayHelpers.waitFor(.playing)

    // Auto-advance to the queued episode, then let the blanket suppression lapse.
    avPlayer.finishEpisode()
    try await PlayHelpers.waitForOnDeck(queuedEpisode)
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(2))
    try await Wait.until(
      { await playManager.ignoreRemoteScrubCommands == false },
      { "Expected remote scrub suppression to end after time advance" }
    )

    // A scrub that lands at the midpoint is honored even though the episode just
    // became current — the guard only rejects scrubs to the very end.
    let midpoint = CMTime.seconds(try #require(sharedState.onDeck?.duration).seconds / 2)
    commandCenterContinuation.yield(
      .playbackPosition(
        midpoint.seconds,
        sourceEpisodeID: queuedEpisode.id,
        eventTimestamp: Date().timeIntervalSinceReferenceDate
      )
    )
    try await PlayHelpers.waitFor(midpoint)
  }

  @Test("time update events update currentTime")
  func timeUpdateEventsUpdateCurrentTime() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    let advancedTime = CMTime.seconds(10)
    avPlayer.advanceTime(to: advancedTime)
    try await PlayHelpers.waitFor(advancedTime)
  }

  @Test("retired time observer cannot update a replacement episode")
  func retiredTimeObserverCannotUpdateReplacementEpisode() async throws {
    await playManager.start()
    let (retiredEpisode, replacementEpisode) = try await Create.twoPodcastEpisodes()
    let fakeRepo = try #require(repo as? FakeRepo)

    try await playManager.load(retiredEpisode)
    let retiredObserver = try #require(avPlayer.timeObservers.values.first)
    try await playManager.load(replacementEpisode)
    fakeRepo.clearAllCalls()

    retiredObserver.block(.seconds(30))
    await Task.yield()
    _ = try await repo.episode(replacementEpisode.id)

    try fakeRepo.expectNoCall(methodName: "updatePlayback")
    let storedReplacement = try #require(try await repo.episode(replacementEpisode.id))
    #expect(storedReplacement.currentTime == .zero)
    #expect(sharedState.onDeck?.currentTime == .zero)
  }

  @Test("time updates throttle database writes to every 3 seconds")
  func timeUpdatesThrottleDatabaseWritesToEvery3Seconds() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    // Verify initial current time is 0
    let initialEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(initialEpisode?.currentTime == .zero)

    // Advance time by 1 second - should NOT write to DB yet
    avPlayer.advanceTime(to: .seconds(1))
    try await PlayHelpers.waitFor(.seconds(1))
    var updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .zero)

    // Advance time by 2 seconds total - should NOT write to DB yet
    avPlayer.advanceTime(to: .seconds(2))
    try await PlayHelpers.waitFor(.seconds(2))
    updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .zero)

    // Advance time by 3 seconds total - SHOULD write to DB now
    avPlayer.advanceTime(to: .seconds(3))
    try await PlayHelpers.waitFor(.seconds(3))
    try await Wait.until(
      { try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime == .seconds(3) },
      { "Expected DB to be updated to 3 seconds" }
    )

    // Advance time by 4 seconds - should NOT write to DB yet (last write was at 3s)
    avPlayer.advanceTime(to: .seconds(4))
    try await PlayHelpers.waitFor(.seconds(4))
    updatedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(updatedEpisode?.currentTime == .seconds(3))

    // Advance time by 6 seconds - SHOULD write to DB again (3s interval passed)
    avPlayer.advanceTime(to: .seconds(6))
    try await PlayHelpers.waitFor(.seconds(6))
    try await Wait.until(
      { try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime == .seconds(6) },
      { "Expected DB to be updated to 6 seconds" }
    )
  }

  @Test("time updates keep publishing while a playback save waits for the writer")
  func timeUpdatesKeepPublishingWhilePlaybackSaveWaits() async throws {
    typealias PlaybackUpdate = MethodCall<
      (episodeID: Episode.ID, currentTime: CMTime, playedFrom: CMTime, now: Date)
    >
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    let fakeRepo = try #require(repo as? FakeRepo)

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    fakeRepo.clearAllCalls()
    fakeRepo.playbackUpdatesHeld(true)

    avPlayer.advanceTime(to: .seconds(3))
    try await fakeRepo.waitForPlaybackUpdateSuspended()
    try await PlayHelpers.waitFor(.seconds(3))
    for second in 4...7 {
      avPlayer.advanceTime(to: .seconds(Double(second)))
      try await PlayHelpers.waitFor(.seconds(Double(second)))
    }
    #expect(fakeRepo.calls(of: PlaybackUpdate.self).map(\.parameters.currentTime) == [.seconds(3)])

    await fakeRepo.releasePlaybackUpdates()
    try await Wait.until(
      { try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime == .seconds(3) },
      { "Expected the held save to store 3 seconds" }
    )
    // Keep ticking, as playback does, until a tick after the held save finishes saves again.
    let avPlayer = avPlayer
    try await Wait.until(
      { @MainActor in
        avPlayer.advanceTime(to: .seconds(8))
        return try await Container.shared.repo().episode(podcastEpisode.id)?.currentTime
          == .seconds(8)
      },
      { "Expected a later tick to store 8 seconds" }
    )
    let updates = fakeRepo.calls(of: PlaybackUpdate.self).map(\.parameters)
    #expect(updates.map(\.currentTime) == [.seconds(3), .seconds(8)])
    #expect(updates.map(\.playedFrom) == [.zero, .seconds(3)])
  }

  @Test("waiting to play time control status updates playstate")
  func waitingToPlayTimeControlStatusUpdatesPlaystate() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    avPlayer.waitingToPlay()
    try await PlayHelpers.waitFor(.waiting)
  }

  @Test("pause saves current position to database immediately")
  func pauseSavesCurrentPositionToDatabaseImmediately() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()

    // Advance time by 1 second - under the 3-second throttle threshold
    avPlayer.advanceTime(to: .seconds(1))
    try await PlayHelpers.waitFor(.seconds(1))

    // Verify DB has NOT been updated yet (due to throttling)
    var savedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(savedEpisode?.currentTime == .zero)

    // Pause should save the current position immediately
    await playManager.pause()
    try await PlayHelpers.waitFor(.paused)

    // Verify DB HAS been updated after pause
    savedEpisode = try await Container.shared.repo().episode(podcastEpisode.id)
    #expect(savedEpisode?.currentTime == .seconds(1))
  }

  @Test("stop nils currentEpisodeID alongside onDeck")
  func stopNilsCurrentEpisodeIDAlongsideOnDeck() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    try await playManager.load(podcastEpisode)
    #expect(sharedState.currentEpisodeID == podcastEpisode.id)

    await playManager.stop()
    try await PlayHelpers.waitForOnDeck(nil)

    #expect(sharedState.currentEpisodeID == nil)
  }

  // MARK: - Toggle

  @Test("toggle pauses a buffering stream")
  func togglePausesBufferingStream() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()
    try await playManager.load(podcastEpisode)
    try await PlayHelpers.play()
    avPlayer.waitingToPlay(waitingReason: .toMinimizeStalls)
    try await PlayHelpers.waitFor(.waiting)

    await playManager.toggle()

    try await PlayHelpers.waitFor(.paused)
    #expect(avPlayer.timeControlStatus == .paused)
  }

  enum LoadPhase: CaseIterable { case audioSession, asset }

  // The audio session phase runs before the outgoing episode leaves the deck;
  // the asset phase runs after.
  private func suspendLoad(
    of podcastEpisode: PodcastEpisode,
    during phase: LoadPhase
  ) async -> (started: AsyncSemaphore, finish: AsyncSemaphore) {
    let started = AsyncSemaphore(value: 0)
    let finish = AsyncSemaphore(value: 0)
    switch phase {
    case .audioSession:
      Container.shared.configureAudioSession.context(.test) {
        {
          started.signal()
          await finish.wait()
          return true
        }
      }
      Container.shared.configureAudioSession.reset(.scope)
    case .asset:
      await episodeAssetLoader.respond(to: podcastEpisode.episode.mediaURL) { _ in
        started.signal()
        await finish.wait()
        return (true, .seconds(60))
      }
    }
    return (started, finish)
  }

  @Test("toggle during a load cancels its pending playback", arguments: LoadPhase.allCases)
  func toggleDuringLoadCancelsPendingPlayback(phase: LoadPhase) async throws {
    await playManager.start()
    let (currentEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    try await playManager.load(currentEpisode)
    let playCount = avPlayer.playCallCount

    let (phaseStarted, finishPhase) = await suspendLoad(of: incomingEpisode, during: phase)
    let incomingPlay = Task { try await playManager.play(incomingEpisode) }
    defer {
      incomingPlay.cancel()
      finishPhase.signal()
    }
    await phaseStarted.wait()

    await playManager.toggle()
    finishPhase.signal()

    #expect(try await incomingPlay.value == .superseded)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.paused)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == playCount)
  }

  @Test("play during a load keeps its pending playback", arguments: LoadPhase.allCases)
  func playDuringLoadKeepsPendingPlayback(phase: LoadPhase) async throws {
    await playManager.start()
    let (currentEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    try await playManager.load(currentEpisode)

    let (phaseStarted, finishPhase) = await suspendLoad(of: incomingEpisode, during: phase)
    let incomingPlay = Task { try await playManager.play(incomingEpisode) }
    defer {
      incomingPlay.cancel()
      finishPhase.signal()
    }
    await phaseStarted.wait()

    await playManager.play()
    finishPhase.signal()

    #expect(try await incomingPlay.value == .ready)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(avPlayer.timeControlStatus == .playing)
  }

  @Test("play during a load plays the loading episode", arguments: LoadPhase.allCases)
  func playDuringLoadPlaysLoadingEpisode(phase: LoadPhase) async throws {
    await playManager.start()
    let (currentEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    try await playManager.load(currentEpisode)

    let (phaseStarted, finishPhase) = await suspendLoad(of: incomingEpisode, during: phase)
    let incomingLoad = Task { try await playManager.load(incomingEpisode) }
    defer {
      incomingLoad.cancel()
      finishPhase.signal()
    }
    await phaseStarted.wait()

    await playManager.play()
    finishPhase.signal()

    #expect(try await incomingLoad.value)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.playing)
    #expect(avPlayer.timeControlStatus == .playing)
  }

  @Test("pause after a play during a load leaves the loaded episode paused")
  func pauseAfterPlayDuringLoadLeavesLoadedEpisodePaused() async throws {
    await playManager.start()
    let (currentEpisode, incomingEpisode) = try await Create.twoPodcastEpisodes()
    try await playManager.load(currentEpisode)
    let playCount = avPlayer.playCallCount

    let (phaseStarted, finishPhase) = await suspendLoad(of: incomingEpisode, during: .asset)
    let incomingLoad = Task { try await playManager.load(incomingEpisode) }
    defer {
      incomingLoad.cancel()
      finishPhase.signal()
    }
    await phaseStarted.wait()

    await playManager.play()
    await playManager.pause()
    finishPhase.signal()

    #expect(try await incomingLoad.value)
    try await PlayHelpers.waitForOnDeck(incomingEpisode)
    try await PlayHelpers.waitFor(.paused)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == playCount)
  }

  @Test("toggle with nothing loaded leaves the next load paused")
  func toggleWithNothingLoadedLeavesNextLoadPaused() async throws {
    await playManager.start()
    let podcastEpisode = try await Create.podcastEpisode()

    await playManager.toggle()
    try await playManager.load(podcastEpisode)

    #expect(sharedState.playbackStatus == .paused)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == 0)
  }
}
