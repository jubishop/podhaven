// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Semaphore
import Testing

@testable import PodHaven

@Suite("of playback intent ownership", .container)
@MainActor struct PlaybackIntentOwnershipTests {
  enum Restoration: CaseIterable { case startup, foreground, widget }
  enum Supersession: CaseIterable {
    case play, stop, missingThenPlay, missingThenStop
    var missing: Bool { self == .missingThenPlay || self == .missingThenStop }
    var stops: Bool { self == .stop || self == .missingThenStop }
  }

  private var playManager: PlayManager { Container.shared.playManager() }
  private var sharedState: SharedState { Container.shared.sharedState() }
  private var repo: FakeRepo { Container.shared.repo() as! FakeRepo }
  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }
  private var assetLoader: FakeEpisodeAssetLoader { Container.shared.fakeEpisodeAssetLoader() }

  @Test(
    "persisted lookup cannot overwrite newer intent",
    arguments: Restoration.allCases,
    Supersession.allCases
  )
  func persistedLookupPreservesNewerIntent(
    restoration: Restoration,
    supersession: Supersession
  ) async throws {
    let (persisted, replacement) = try await Create.twoPodcastEpisodes()
    let storedID = supersession.missing ? Episode.ID(rawValue: -1) : persisted.id
    storedID.store(to: Container.shared.standardDefaults(), forKey: "currentEpisodeID")
    PlayHelpers.setupCommandHandling()
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let restoring = Task {
      await LogCapture.withSink { sink in
        switch restoration {
        case .startup: await playManager.start()
        case .foreground: await playManager.restorePersistedEpisodeForForeground()
        case .widget: await playManager.play(origin: .widget)
        }
        return sink.captured()
      }
    }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    if supersession.stops {
      await playManager.stop()
    } else {
      try await playManager.play(replacement)
    }
    let newerRevision = playManager.playbackRequestRevision
    let playCount = avPlayer.playCallCount
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    let staleLogs = await restoring.value

    #expect(playManager.playbackRequestRevision == newerRevision)
    #expect(avPlayer.playCallCount == playCount)
    if supersession.stops {
      #expect(sharedState.currentEpisodeID == nil)
      #expect(sharedState.onDeck == nil)
      #expect(avPlayer.current == nil)
      #expect(sharedState.playbackStatus == .stopped)
    } else {
      #expect(sharedState.currentEpisodeID == replacement.id)
      #expect(sharedState.onDeck?.id == replacement.id)
      #expect(
        (avPlayer.current?.asset as? AVURLAsset)?.url == replacement.episode.mediaURL.rawValue
      )
      #expect(avPlayer.timeControlStatus == .playing)
    }
    #expect(!staleLogs.contains { $0.message.contains("event=playRequest") })
  }

  @Test("obsolete widget restoration cannot consume a newer pending play")
  func obsoleteRestorationPreservesPendingPlay() async throws {
    let (persisted, replacement) = try await Create.twoPodcastEpisodes()
    persisted.id.store(to: Container.shared.standardDefaults(), forKey: "currentEpisodeID")
    PlayHelpers.setupCommandHandling()
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let restoring = Task {
      await LogCapture.withSink { sink in
        await playManager.play(origin: .widget)
        return sink.captured()
      }
    }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: replacement.episode.mediaURL) { _ in
      entered.signal()
      await release.wait()
      return (true, .seconds(60))
    }
    let playing = Task { try await playManager.play(replacement) }
    defer { release.signal() }
    await entered.wait()
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    let staleLogs = await restoring.value
    release.signal()
    _ = try await playing.value

    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 1)
    #expect(!staleLogs.contains { $0.message.contains("event=playRequest") })
  }

  @Test(
    "stop revokes an accepted load even when asset work ignores cancellation",
    arguments: [false, true]
  )
  func stopRevokesAcceptedLoad(cancelled: Bool) async throws {
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode()
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: episode.episode.mediaURL) { _ in
      entered.signal()
      await release.wait()
      return (true, .seconds(60))
    }
    let loading = Task { try await playManager.load(episode) }
    defer { release.signal() }
    await entered.wait()
    let beforeStop = playManager.playbackRequestRevision
    let startStop = AsyncSemaphore(value: 0)
    let stopping = Task {
      await startStop.wait()
      await playManager.stop()
    }
    if cancelled { stopping.cancel() }
    startStop.signal()
    try await Wait.until(
      { @MainActor in playManager.playbackRequestRevision != beforeStop },
      { "Expected stop to accept a new playback request" }
    )
    release.signal()
    await stopping.value
    await #expect(throws: CancellationError.self) { try await loading.value }

    #expect(sharedState.onDeck == nil)
    #expect(sharedState.currentEpisodeID == nil)
    #expect(avPlayer.current == nil)
    #expect(sharedState.playbackStatus == .stopped)
  }

  @Test("a newer play survives stop waiting for its predecessor")
  func newerPlaySurvivesStopCleanup() async throws {
    PlayHelpers.setupCommandHandling()
    let (predecessor, replacement) = try await Create.twoPodcastEpisodes()
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: predecessor.episode.mediaURL) { _ in
      entered.signal()
      await release.wait()
      return (true, .seconds(60))
    }
    let loading = Task { try await playManager.load(predecessor) }
    defer { release.signal() }
    await entered.wait()
    let beforeStop = playManager.playbackRequestRevision
    let stopping = Task { await playManager.stop() }
    try await Wait.until(
      { @MainActor in playManager.playbackRequestRevision != beforeStop },
      { "Expected stop to accept a new playback request" }
    )
    try await playManager.play(replacement)
    release.signal()
    await stopping.value
    await #expect(throws: CancellationError.self) { try await loading.value }

    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(sharedState.currentEpisodeID == replacement.id)
    #expect((avPlayer.current?.asset as? AVURLAsset)?.url == replacement.episode.mediaURL.rawValue)
    #expect(avPlayer.timeControlStatus == .playing)
  }

  @Test(
    "superseded media-services lookup preserves newer intent",
    arguments: Supersession.allCases
  )
  func supersededMediaServicesLookup(supersession: Supersession) async throws {
    let stops = supersession.stops
    let (interrupted, replacement) = try await Create.twoPodcastEpisodes()
    try await prepareMediaServicesRecovery(interrupted)
    if supersession.missing {
      _ = try await Container.shared.appDB().writer
        .write { db in
          try Episode.withIDs([interrupted.id]).deleteAll(db)
        }
    }
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let recovering = Task {
      await LogCapture.withSink { sink in
        await playManager.play(origin: .widget)
        return sink.captured()
      }
    }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    if stops {
      await playManager.stop()
    } else {
      try await playManager.play(replacement)
    }
    let newerRevision = playManager.playbackRequestRevision
    let playCount = avPlayer.playCallCount
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    let staleLogs = await recovering.value

    #expect(playManager.playbackRequestRevision == newerRevision)
    #expect(avPlayer.playCallCount == playCount)
    #expect(sharedState.onDeck?.id == (stops ? nil : replacement.id))
    #expect(sharedState.currentEpisodeID == (stops ? nil : replacement.id))
    #expect(!staleLogs.contains { $0.message.contains("event=playRequest") })
    if stops { #expect(avPlayer.current == nil) }
  }

  @Test("normal widget media-services recovery retains its request ownership")
  func normalMediaServicesRecoveryRetainsOwnership() async throws {
    let episode = try await Create.podcastEpisode()
    try await prepareMediaServicesRecovery(episode)
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let recovering = Task {
      await LogCapture.withSink { sink in
        await playManager.play(origin: .widget)
        return sink.captured()
      }
    }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    let recoveryRevision = playManager.playbackRequestRevision
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    let staleLogs = await recovering.value

    #expect(playManager.playbackRequestRevision == recoveryRevision)
    #expect(sharedState.onDeck?.id == episode.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(
      staleLogs.contains {
        $0.message.contains("event=playRequest requestID=\(recoveryRevision) origin=widget")
      }
    )
  }

  @Test("superseded recovery failure cannot clear a newer pending play")
  func supersededRecoveryFailurePreservesPendingPlay() async throws {
    let (interrupted, replacement) = try await Create.twoPodcastEpisodes()
    try await prepareMediaServicesRecovery(interrupted)
    let recoveryEntered = AsyncSemaphore(value: 0)
    let releaseRecovery = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: interrupted.episode.mediaURL) { _ in
      recoveryEntered.signal()
      await releaseRecovery.wait()
      throw TestError.simulatedFailure
    }
    let recovering = Task { await playManager.play(origin: .widget) }
    defer { releaseRecovery.signal() }
    await recoveryEntered.wait()

    let replacementEntered = AsyncSemaphore(value: 0)
    let releaseReplacement = AsyncSemaphore(value: 0)
    await assetLoader.respond(to: replacement.episode.mediaURL) { _ in
      replacementEntered.signal()
      await releaseReplacement.wait()
      return (true, .seconds(60))
    }
    let replacing = Task { try await playManager.play(replacement) }
    defer { releaseReplacement.signal() }
    await replacementEntered.wait()
    Container.shared.alert().config = nil
    releaseRecovery.signal()
    await recovering.value
    #expect(Container.shared.alert().config == nil)
    releaseReplacement.signal()
    _ = try await replacing.value

    #expect(sharedState.onDeck?.id == replacement.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 1)
  }

  @Test("stale foreground lookup preserves a newer widget request for the same episode")
  func staleForegroundLookupPreservesSameEpisodeRequest() async throws {
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode()
    let audioSession = Container.shared.fakeAudioSession()
    audioSession.configureError { $0 = TestError.simulatedFailure }
    try await playManager.play(episode)
    audioSession.configureError { $0 = nil }
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let restoring = Task {
      await LogCapture.withSink { sink in
        await playManager.restorePersistedEpisodeForForeground()
        return sink.captured()
      }
    }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    try await playManager.play(episode, origin: .widget)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    let staleLogs = await restoring.value

    #expect(sharedState.onDeck?.id == episode.id)
    #expect(avPlayer.timeControlStatus == .playing)
    #expect(avPlayer.playCallCount == 1)
    #expect(!staleLogs.contains { $0.message.contains("event=widgetRouteRecoveryCancelled") })
  }

  private func prepareMediaServicesRecovery(_ episode: PodcastEpisode) async throws {
    PlayHelpers.setupCommandHandling()
    try await playManager.load(episode)
    let oldPlayer = avPlayer
    Container.shared.notifier()
      .continuation(for: AVAudioSession.mediaServicesWereResetNotification)
      .yield(Notification(name: AVAudioSession.mediaServicesWereResetNotification))
    try await Wait.until(
      { @MainActor in
        avPlayer != oldPlayer
          && Container.shared.alert().config?.title == "Audio Services Restarted"
      },
      { "Expected media-services reset to finish" }
    )
  }
}
