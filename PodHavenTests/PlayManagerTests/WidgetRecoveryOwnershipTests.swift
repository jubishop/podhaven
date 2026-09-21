// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of widget recovery ownership across actor hops", .container)
@MainActor struct WidgetRecoveryOwnershipTests {
  enum Command: CaseIterable, Sendable { case pause, play, stop, replace }

  private var manager: PlayManager { Container.shared.playManager() }
  private var player: PodAVPlayer { Container.shared.podAVPlayer() }
  private var avPlayer: FakeAVPlayer { Container.shared.avPlayer() as! FakeAVPlayer }
  private var sleeper: FakeSleeper { Container.shared.sleeper() as! FakeSleeper }
  private var widget: WidgetState { Container.shared.widgetState() }

  @Test(
    "a status snapshot cannot reinstall or clear superseding recovery",
    arguments: Command.allCases
  )
  func statusSnapshotPreservesNewRequest(command: Command) async throws {
    let replacement = try await Create.podcastEpisode()
    try await preparePlayback()
    let source = try #require(player.eventSource)
    let observations = avPlayer.statusObservations
    avPlayer.statusObservations = []
    avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
    avPlayer.statusObservations = observations
    await manager.setStatus(.waiting)

    try await statusHandoff(
      manager: manager,
      event: PodAVPlayerEvent(source: source, value: .waiting),
      command: command,
      replacement: replacement
    )

    try await assertNewRequest(command, replacement: replacement)
    let recovery = await manager.widgetRouteRecovery
    if command == .play || command == .replace {
      #expect(recovery?.requestID == manager.playbackRequestRevision)
    } else {
      #expect(recovery == nil)
    }
  }

  @PlayActor private func statusHandoff(
    manager: PlayManager,
    event: PodAVPlayerEvent<PlaybackStatus>,
    command: Command,
    replacement: PodcastEpisode
  ) async throws {
    let revision = manager.playbackRequestRevision
    let stale = Task.immediate {
      await manager.handleWidgetRouteRecoveryStatus(event)
    }
    let newer = Task.immediate {
      try await Self.supersede(manager, command: command, replacement: replacement)
    }
    #expect(manager.playbackRequestRevision != revision)
    try await newer.value
    await stale.value
  }

  @Test("a retry action cannot overtake a newer request", arguments: Command.allCases)
  func retryActionPreservesNewRequest(command: Command) async throws {
    let replacement = try await Create.podcastEpisode()
    let manager = manager
    let newer = ThreadSafe<Task<Void, any Error>?>(nil)
    try await LogCapture.withSink(
      onCapture: { entry in
        guard entry.message.contains("event=widgetRouteRecoveryAttempt") else { return }
        let task = Task.immediate { @PlayActor in
          try await Self.supersede(manager, command: command, replacement: replacement)
        }
        newer(task)
      }
    ) { _ in
      try await preparePlayback()
      avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
      try await PlayHelpers.waitFor(.waiting)
      try await sleeper.waitForSleepRequests(for: .seconds(1))
      let recoveryTask = try #require(await manager.widgetRouteRecoveryTask)
      await sleeper.advanceTime(by: .seconds(1))
      let newerTask = try await Wait.forValue { newer() }
      try await newerTask.value
      await recoveryTask.value

      try await assertNewRequest(command, replacement: replacement)
      #expect(avPlayer.playCallCount == (command == .play || command == .replace ? 2 : 1))
      let recovery = await manager.widgetRouteRecovery
      #expect(recovery == nil || recovery?.requestID == manager.playbackRequestRevision)
    }
  }

  @Test("timeout position saving cannot publish over a newer request", arguments: Command.allCases)
  func timeoutCompletionPreservesNewRequest(command: Command) async throws {
    let replacement = try await Create.podcastEpisode()
    try await preparePlayback()
    avPlayer.waitingToPlay(waitingReason: .evaluatingBufferingRate)
    try await PlayHelpers.waitFor(.waiting)
    try await sleeper.waitForSleepRequests(for: .seconds(1))
    await sleeper.advanceTime(by: .seconds(1))
    try await sleeper.waitForSleepRequests(for: .seconds(10))
    let recoveryTask = try #require(await manager.widgetRouteRecoveryTask)
    let entered = AsyncSemaphore(value: 0)
    let release = AsyncSemaphore(value: 0)
    let repo = Container.shared.repo() as! FakeRepo
    await repo.beforeNextCurrentTimeUpdate {
      entered.signal()
      await release.wait()
    }
    defer { release.signal() }
    await sleeper.advanceTime(by: .seconds(10))
    await entered.wait()
    try await Self.supersede(manager, command: command, replacement: replacement)
    try await assertNewRequest(command, replacement: replacement)
    release.signal()
    await recoveryTask.value
    try await assertNewRequest(command, replacement: replacement)
    let recovery = await manager.widgetRouteRecovery
    #expect(recovery == nil || recovery?.requestID == manager.playbackRequestRevision)
  }

  private func preparePlayback() async throws {
    Container.shared.stateManager().start()
    Container.shared.widgetSnapshotWriter().start()
    PlayHelpers.setupCommandHandling()
    let cached = try Create.unsavedEpisode(cachedFilename: "widget-ownership.mp3")
    let episode = try await Create.podcastEpisode(cached)
    try await manager.play(episode, origin: .widget)
    try await PlayHelpers.waitFor(.playing)
    try await Wait.until(
      { @MainActor in widget.playbackStatus == .playing },
      { "Expected initial widget playback" }
    )
  }

  @PlayActor private static func supersede(
    _ manager: PlayManager,
    command: Command,
    replacement: PodcastEpisode
  ) async throws {
    switch command {
    case .pause: await manager.pause()
    case .play: await manager.play(origin: .widget)
    case .stop: await manager.stop()
    case .replace: try await manager.play(replacement, origin: .widget)
    }
  }

  private func assertNewRequest(_ command: Command, replacement: PodcastEpisode) async throws {
    let expected: PlaybackStatus =
      command == .pause ? .paused : command == .stop ? .stopped : .playing
    #expect(player.playbackStatus() == (command == .stop ? .paused : expected))
    try await PlayHelpers.waitFor(expected)
    try await Wait.until(
      { @MainActor in widget.playbackStatus == expected },
      { @MainActor in "Expected widget \(expected), got \(widget.playbackStatus)" }
    )
    if command == .replace {
      #expect(player.episodeID == replacement.id)
    } else if command == .stop {
      #expect(avPlayer.current == nil)
    }
  }
}
