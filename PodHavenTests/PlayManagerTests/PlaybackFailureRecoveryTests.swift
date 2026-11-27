// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of automatic playback failure recovery", .container, .timeLimit(.minutes(5)))
@MainActor struct PlaybackFailureRecoveryTests {
  enum NotificationCommand: CaseIterable {
    case play, pause, togglePause, resume, toggleResume
    var shouldRecover: Bool { self != .pause && self != .togglePause }
  }

  enum Lookup: CaseIterable { case diagnostics, reload }
  enum Command: CaseIterable { case sameEpisode, differentEpisode, pause, stop }
  enum FailureSignal: CaseIterable { case itemStatus, failedToPlayToEnd }

  private var playManager: PlayManager { Container.shared.playManager() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var repo: FakeRepo { Container.shared.repo() as! FakeRepo }
  private var queue: FakeQueue { Container.shared.queue() as! FakeQueue }
  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }
  private var assetLoader: FakeEpisodeAssetLoader { Container.shared.fakeEpisodeAssetLoader() }
  private var alert: Alert { Container.shared.alert() }

  @Test(
    "recovery lookups preserve newer play, pause, and stop",
    arguments: Lookup.allCases,
    Command.allCases
  )
  func lookupPreservesNewerIntent(lookup: Lookup, command: Command) async throws {
    let (failed, replacement) = try await Create.twoPodcastEpisodes()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let recovery = try await suspendRecovery(at: lookup)

    switch command {
    case .sameEpisode: try await playManager.play(failed)
    case .differentEpisode: try await playManager.play(replacement)
    case .pause: await playManager.pause()
    case .stop: await playManager.stop()
    }
    let revision = playManager.playbackRequestRevision
    let currentURL = PlayHelpers.currentAssetURL
    let onDeckID = sharedState.onDeck?.id
    let playCount = avPlayer.playCallCount
    let queuedIDs = try await PlayHelpers.queuedEpisodeIDs
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    await recovery.value

    #expect(playManager.playbackRequestRevision == revision)
    #expect(PlayHelpers.currentAssetURL == currentURL)
    #expect(sharedState.onDeck?.id == onDeckID)
    #expect(avPlayer.playCallCount == playCount)
    #expect(try await PlayHelpers.queuedEpisodeIDs == queuedIDs)
    #expect(alert.config == nil)
  }

  @Test("obsolete recovery lookup cannot consume pending playback", arguments: [false, true])
  func lookupPreservesPendingPlayback(sameEpisode: Bool) async throws {
    let (failed, different) = try await Create.twoPodcastEpisodes()
    let replacement = sameEpisode ? failed : different
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let recovery = try await suspendRecovery(at: .reload)
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: replacement.episode.mediaURL) { _ in
      entered.signal()
      await release.wait()
      return (true, .seconds(60))
    }
    let playing = Task { try await playManager.play(replacement) }
    defer { release.signal() }
    try await entered.waitUnlessCancelled()
    let revision = playManager.playbackRequestRevision
    await assetLoader.clearCustomHandler(for: replacement.episode)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    await recovery.value
    #expect(playManager.playbackRequestRevision == revision)
    release.signal()
    _ = try await playing.value

    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 2)
    #expect(alert.config == nil)
  }

  @Test("a pause during the recovery load prevents automatic resume")
  func pauseDuringLoad() async throws {
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: failed.episode.mediaURL) { _ in
      entered.signal()
      await release.wait()
      return (true, .seconds(60))
    }
    let recovery = Task { await playManager.handlePlaybackFailure() }
    defer { release.signal() }
    try await entered.waitUnlessCancelled()
    await playManager.pause()
    let revision = playManager.playbackRequestRevision
    release.signal()
    await recovery.value

    #expect(playManager.playbackRequestRevision == revision)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == 1)
    #expect(alert.config == nil)
  }

  @Test("stale failed recovery cannot consume a newer pending play", arguments: [false, true])
  func failedLoadPreservesPendingPlayback(sameEpisode: Bool) async throws {
    let (failed, different) = try await Create.twoPodcastEpisodes()
    let replacement = sameEpisode ? failed : different
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let failedEntered = AsyncSemaphore(value: 0)
    let failedRelease = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: failed.episode.mediaURL) { _ in
      failedEntered.signal()
      await failedRelease.wait()
      throw TestError.simulatedFailure
    }
    let recovery = Task { await playManager.handlePlaybackFailure() }
    defer { failedRelease.signal() }
    try await failedEntered.waitUnlessCancelled()
    let newerEntered = AsyncSemaphore(value: 0)
    let newerRelease = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: replacement.episode.mediaURL) { _ in
      newerEntered.signal()
      await newerRelease.wait()
      return (true, .seconds(60))
    }
    let playing = Task { try await playManager.play(replacement) }
    defer { newerRelease.signal() }
    try await newerEntered.waitUnlessCancelled()
    let revision = playManager.playbackRequestRevision
    failedRelease.signal()
    await recovery.value
    #expect(playManager.playbackRequestRevision == revision)
    #expect(alert.config == nil)
    newerRelease.signal()
    _ = try await playing.value

    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 2)
  }

  @Test("fallback cannot requeue or alert over a newer play", arguments: [false, true])
  func fallbackPreservesNewerPlayback(sameEpisode: Bool) async throws {
    Container.shared.fakeContinuousClock().freeze()
    let (failed, different) = try await Create.twoPodcastEpisodes()
    let replacement = sameEpisode ? failed : different
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    await playManager.handlePlaybackFailure()
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    queue.beforeUnshiftEpisode { _ in
      entered.signal()
      await release.wait()
    }
    let recovery = Task { await playManager.handlePlaybackFailure() }
    defer { release.signal() }
    try await entered.waitUnlessCancelled()
    try await playManager.play(replacement)
    let revision = playManager.playbackRequestRevision
    release.signal()
    await recovery.value

    #expect(playManager.playbackRequestRevision == revision)
    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(alert.config == nil)
  }

  @Test("recovery succeeds once then debounces and returns the episode to Up Next")
  func successfulRecoveryAndDebounce() async throws {
    Container.shared.fakeContinuousClock().freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let originalItem = avPlayer.current as? FakeAVPlayerItem
    await playManager.handlePlaybackFailure()
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.current as? FakeAVPlayerItem !== originalItem)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 2)
    #expect(alert.config == nil)

    await playManager.handlePlaybackFailure()
    #expect(sharedState.onDeck == nil)
    #expect(avPlayer.current == nil)
    #expect(avPlayer.playCallCount == 2)
    #expect(try await PlayHelpers.queuedEpisodeIDs == [failed.id])
    #expect(alert.config != nil)
  }

  @Test("a repeat failure recovers again once the debounce interval has passed")
  func recoveryAfterDebounceInterval() async throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    await playManager.handlePlaybackFailure()
    let recoveredItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    #expect(avPlayer.playCallCount == 2)

    clock.advance(by: await playManager.recoveryDebounceInterval)
    await playManager.handlePlaybackFailure()

    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.current as? FakeAVPlayerItem !== recoveredItem)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 3)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(alert.config == nil)
  }

  @Test("superseded reload lookup does not consume the next recovery attempt")
  func supersededLookupDoesNotDebounce() async throws {
    Container.shared.fakeContinuousClock().freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let recovery = try await suspendRecovery(at: .reload)
    try await playManager.play(failed)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    await recovery.value

    await playManager.handlePlaybackFailure()

    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 3)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(alert.config == nil)
  }

  @Test("item failure during playback recovers once, then returns the episode to Up Next")
  func itemFailureDuringPlayback() async throws {
    Container.shared.fakeContinuousClock().freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let originalItem = try #require(avPlayer.current as? FakeAVPlayerItem)

    originalItem.setStatus(.failed)
    let recoveredItem = try await waitForRecoveredItem(replacing: originalItem, status: .playing)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.playCallCount == 2)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(alert.config == nil)

    recoveredItem.setStatus(.failed)
    try await Wait.until({ await alert.config != nil }, { "Expected a playback failure alert" })
    #expect(sharedState.onDeck == nil)
    #expect(avPlayer.current == nil)
    #expect(avPlayer.playCallCount == 2)
    #expect(try await PlayHelpers.queuedEpisodeIDs == [failed.id])
  }

  @Test("item failure while paused reloads the episode without resuming playback")
  func itemFailureWhilePaused() async throws {
    Container.shared.fakeContinuousClock().freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    await playManager.pause()
    let originalItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    let playCount = avPlayer.playCallCount

    originalItem.setStatus(.failed)
    let recoveredItem = try await waitForRecoveredItem(replacing: originalItem, status: .paused)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == playCount)
    #expect(try await PlayHelpers.queuedEpisodeIDs.isEmpty)
    #expect(alert.config == nil)

    recoveredItem.setStatus(.failed)
    try await Wait.until({ await alert.config != nil }, { "Expected a playback failure alert" })
    #expect(sharedState.onDeck == nil)
    #expect(avPlayer.current == nil)
    #expect(avPlayer.playCallCount == playCount)
    #expect(try await PlayHelpers.queuedEpisodeIDs == [failed.id])
  }

  @Test("item failure after a route-loss pause reloads the episode without resuming playback")
  func itemFailureAfterRouteLossPause() async throws {
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    try await PlayHelpers.loseAudioRoute()
    let originalItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    let playCount = avPlayer.playCallCount

    originalItem.setStatus(.failed)
    _ = try await waitForRecoveredItem(replacing: originalItem, status: .paused)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.timeControlStatus == .paused)
    #expect(avPlayer.playCallCount == playCount)
    #expect(alert.config == nil)
  }

  @Test("an item failure during another episode's audio-session setup lets that episode play")
  func itemFailureDuringOtherEpisodeLoad() async throws {
    try await LogCapture.withSink { sink in
      let (failed, selected) = try await Create.twoPodcastEpisodes()
      let requestID = UUID()
      let (_, selection) = try await failItemDuringSelection(
        of: selected,
        playing: failed,
        requestID: requestID,
        in: sink
      )
      defer { selection.cancel() }

      try await PlayHelpers.recoverAudioSessionConfiguration()

      #expect(try await selection.value == .ready)
      try await yieldForSpuriousAsyncWork()
      #expect(playManager.playbackRequestRevision == requestID)
      #expect(sharedState.onDeck?.id == selected.id)
      #expect(PlayHelpers.currentAssetURL == selected.episode.mediaURL.rawValue)
      #expect(avPlayer.timeControlStatus == .playing)
      #expect(avPlayer.playCallCount == 2)
      #expect(await assetLoader.responseCount(for: failed.episode.mediaURL) == 1)
      #expect(alert.config == nil)
    }
  }

  @Test(
    "an item failure while an episode finishes lets the auto-advance play the next episode",
    arguments: FailureSignal.allCases
  )
  func itemFailureDuringFinishAdvances(signal: FailureSignal) async throws {
    try await LogCapture.withSink { sink in
      let (finished, next) = try await Create.twoPodcastEpisodes()
      if signal == .failedToPlayToEnd { loadRealPlayerItems() }
      PlayHelpers.setupCommandHandling()
      try await queue.unshift(next.id)
      try await playManager.play(finished)
      let failedItem = avPlayer.current
      let revision = playManager.playbackRequestRevision
      let marking = AsyncSemaphore(value: 0)
      let release = AsyncSemaphore(value: 0)
      await repo.afterNextMarkFinished { _ in
        marking.signal()
        await release.wait()
      }
      let finishing = Task { await playManager.finishEpisode(finished.id) }
      defer { release.signal() }
      try await marking.waitUnlessCancelled()

      switch signal {
      case .itemStatus:
        try #require(failedItem as? FakeAVPlayerItem).setStatus(.failed)
      case .failedToPlayToEnd:
        Container.shared.notifier()
          .continuation(for: AVPlayerItem.failedToPlayToEndTimeNotification)
          .yield(
            Notification(
              name: AVPlayerItem.failedToPlayToEndTimeNotification,
              object: try #require(failedItem as? AVPlayerItem)
            )
          )
      }
      try await waitForItemFailureHandling(in: sink, preserving: revision)
      release.signal()
      await finishing.value

      try await PlayHelpers.waitForOnDeck(next)
      try await PlayHelpers.waitFor(.playing)
      try await yieldForSpuriousAsyncWork()
      #expect(sharedState.onDeck?.id == next.id)
      #expect((avPlayer.current?.asset as? AVURLAsset)?.url == next.episode.mediaURL.rawValue)
      #expect(avPlayer.playCallCount == 2)
      #expect(alert.config == nil)
    }
  }

  @Test("an item failure is recovered once another episode's audio-session setup fails")
  func itemFailureRecoveredAfterOtherEpisodeLoadFails() async throws {
    try await LogCapture.withSink { sink in
      let (failed, selected) = try await Create.twoPodcastEpisodes()
      let requestID = UUID()
      let (failedItem, selection) = try await failItemDuringSelection(
        of: selected,
        playing: failed,
        requestID: requestID,
        in: sink
      )
      defer { selection.cancel() }

      try await PlayHelpers.advanceAudioSessionRetryBackoff()
      #expect(try await selection.value == .unavailable)

      _ = try await waitForRecoveredItem(replacing: failedItem, status: .playing)
      #expect(sharedState.onDeck?.id == failed.id)
      #expect(await assetLoader.responseCount(for: failed.episode.mediaURL) == 2)
      #expect(await assetLoader.responseCount(for: selected.episode.mediaURL) == 0)
    }
  }

  @Test("recovery keeps Stop After Current Episode, so the reloaded episode stops at its end")
  func recoveryKeepsStopAfterCurrentEpisode() async throws {
    let (failed, queued) = try await Create.twoPodcastEpisodes()
    PlayHelpers.setupCommandHandling()
    try await queue.unshift(queued.id)
    try await playManager.play(failed)
    sharedState.setStopAfterCurrentEpisode(true)
    let originalItem = try #require(avPlayer.current as? FakeAVPlayerItem)

    originalItem.setStatus(.failed)
    _ = try await waitForRecoveredItem(replacing: originalItem, status: .playing)
    #expect(sharedState.stopAfterCurrentEpisode)
    await playManager.finishEpisode(failed.id)

    try await PlayHelpers.waitForFinished(failed)
    #expect(sharedState.playbackStatus == .stopped)
    #expect(sharedState.onDeck == nil)
    #expect(avPlayer.current == nil)
    #expect(try await PlayHelpers.queuedEpisodeIDs == [queued.id])
    #expect(!sharedState.stopAfterCurrentEpisode)
  }

  @Test(
    "recovery keeps the episode's silence choices until a repeat failure returns it to Up Next",
    arguments: [false, true]
  )
  func recoveryKeepsSilenceChoices(paused: Bool) async throws {
    Container.shared.fakeContinuousClock().freeze()
    let failed = try await Create.podcastEpisode()
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    if paused { await playManager.pause() }
    let status: PlaybackStatus = paused ? .paused : .playing
    let silenceOverride = SilenceOverride(episodeID: failed.id, mode: .aggressive)
    let quietAudioProtectionOverride = QuietAudioProtectionOverride(
      episodeID: failed.id,
      protection: .low
    )
    let silenceSourceRejection = SilenceSourceRejection(
      episodeID: failed.id,
      filename: "rejected.mp3",
      generation: "rejected"
    )
    sharedState.$silenceOverride.new(silenceOverride)
    sharedState.$quietAudioProtectionOverride.new(quietAudioProtectionOverride)
    sharedState.$silenceSourceRejection.new(silenceSourceRejection)
    let originalItem = try #require(avPlayer.current as? FakeAVPlayerItem)

    originalItem.setStatus(.failed)
    let recoveredItem = try await waitForRecoveredItem(replacing: originalItem, status: status)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(sharedState.silenceOverride == silenceOverride)
    #expect(sharedState.quietAudioProtectionOverride == quietAudioProtectionOverride)
    #expect(sharedState.silenceSourceRejection == silenceSourceRejection)
    #expect(sharedState.effectiveSilenceMode == .aggressive)
    #expect(sharedState.effectiveQuietAudioProtection == .low)

    recoveredItem.setStatus(.failed)
    try await Wait.until({ await alert.config != nil }, { "Expected a playback failure alert" })
    #expect(try await PlayHelpers.queuedEpisodeIDs == [failed.id])
    #expect(sharedState.silenceOverride == nil)
    #expect(sharedState.quietAudioProtectionOverride == nil)
    #expect(sharedState.silenceSourceRejection == nil)
  }

  @Test("failure notification honors playback ownership", arguments: NotificationCommand.allCases)
  func notificationHonorsPlaybackOwnership(command: NotificationCommand) async throws {
    let failed = try await Create.podcastEpisode()
    loadRealPlayerItems()
    let release = AsyncSemaphore(value: 0)
    let processed = AsyncSemaphore(value: 0)
    let delivered = ThreadSafe(false)
    let notifier = Container.shared.notifier()
    let item = ThreadSafe<AVPlayerItem?>(nil)
    Container.shared.notifications.context(.test) {
      { name in
        guard name == AVPlayerItem.failedToPlayToEndTimeNotification else {
          return notifier.stream(for: name)
        }
        return AsyncStream(unfolding: {
          guard !delivered() else {
            processed.signal()
            return nil
          }
          await release.wait()
          delivered(true)
          return Notification(
            name: name,
            object: item(),
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: TestError.simulatedFailure]
          )
        })
      }
    }
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    item(try #require(avPlayer.current as? AVPlayerItem))
    switch command {
    case .play: break
    case .pause: await playManager.pause()
    case .togglePause: await playManager.toggle()
    case .resume:
      await playManager.pause()
      await playManager.play()
    case .toggleResume:
      await playManager.toggle()
      await playManager.toggle()
    }
    let revision = playManager.playbackRequestRevision
    let playCount = avPlayer.playCallCount
    release.signal()
    try await processed.waitUnlessCancelled()

    #expect((playManager.playbackRequestRevision != revision) == command.shouldRecover)
    #expect(sharedState.onDeck?.id == failed.id)
    #expect(avPlayer.timeControlStatus == (command.shouldRecover ? .playing : .paused))
    #expect(avPlayer.playCallCount == playCount + (command.shouldRecover ? 1 : 0))
    #expect(alert.config == nil)
  }

  @Test("failure notification without an error still recovers playback")
  func notificationWithoutErrorRecovers() async throws {
    try await LogCapture.withSink { sink in
      let failed = try await Create.podcastEpisode()
      loadRealPlayerItems()
      PlayHelpers.setupCommandHandling()
      try await playManager.play(failed)
      let failedItem = try #require(avPlayer.current as? AVPlayerItem)
      let revision = playManager.playbackRequestRevision
      let playCount = avPlayer.playCallCount

      Container.shared.notifier()
        .continuation(for: AVPlayerItem.failedToPlayToEndTimeNotification)
        .yield(
          Notification(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: failedItem)
        )

      try await Wait.until(
        { @MainActor in
          avPlayer.playCallCount == playCount + 1
            && avPlayer.current as? AVPlayerItem !== failedItem
        },
        { @MainActor in "Expected playback to recover onto a new player item" }
      )
      #expect(playManager.playbackRequestRevision != revision)
      #expect(sharedState.onDeck?.id == failed.id)
      #expect(avPlayer.timeControlStatus == .playing)
      #expect(alert.config == nil)
      #expect(
        sink.captured()
          .contains {
            $0.level == .warning
              && $0.message.contains("failed to play to end time without an error")
          }
      )
    }
  }

  private func loadRealPlayerItems() {
    Container.shared.loadEpisodeAsset.context(.test) {
      { @concurrent url in
        await EpisodeAsset(
          isPlayable: true,
          duration: .seconds(60),
          playerItemFactory: { AVPlayerItem(url: url) }
        )
      }
    }
  }

  private func waitForRecoveredItem(
    replacing failedItem: FakeAVPlayerItem,
    status: PlaybackStatus
  ) async throws -> FakeAVPlayerItem {
    try await Wait.forValue { @MainActor in
      guard let item = avPlayer.current as? FakeAVPlayerItem, item !== failedItem,
        sharedState.playbackStatus == status
      else { return nil }
      return item
    }
  }

  // Plays `failed`, then fails its item while the selection's audio-session setup
  // backs off.
  private func failItemDuringSelection(
    of selected: PodcastEpisode,
    playing failed: PodcastEpisode,
    requestID: UUID,
    in sink: LogCapture.Sink
  ) async throws -> (FakeAVPlayerItem, Task<PlayManager.SelectionResult, any Error>) {
    PlayHelpers.setupCommandHandling()
    try await playManager.play(failed)
    let failedItem = try #require(avPlayer.current as? FakeAVPlayerItem)
    PlayHelpers.failAudioSessionConfiguration()
    let selection = Task { try await playManager.play(selected, requestID: requestID) }
    try await PlayHelpers.waitForFailedAudioSessionConfigurationAttempt()
    failedItem.setStatus(.failed)
    try await waitForItemFailureHandling(in: sink, preserving: requestID)
    return (failedItem, selection)
  }

  // Returns once the failure either yields to the newer transition or starts a
  // recovery that supersedes it.
  private func waitForItemFailureHandling(
    in sink: LogCapture.Sink,
    preserving revision: UUID
  ) async throws {
    try await Wait.until(
      { @MainActor in
        playManager.playbackRequestRevision != revision
          || sink.captured().contains { $0.message.contains("event=itemFailureYield") }
      },
      { "Expected the item failure to yield to the newer transition or supersede it" }
    )
  }

  private func suspendRecovery(at lookup: Lookup) async throws -> Task<Void, Never> {
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let recovery = Task { await playManager.handlePlaybackFailure() }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    if lookup == .reload {
      repo.pendingPodcastEpisodeFetchSuspend(true)
      await repo.resumeAllPodcastEpisodeFetchSuspensions()
      try await repo.waitForPodcastEpisodeFetchSuspended()
    }
    return recovery
  }
}
