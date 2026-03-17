// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetSnapshotWriter tests", .container)
@MainActor class WidgetSnapshotWriterTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.widgetSnapshotWriter) private var writer

  nonisolated private var widgetState: WidgetState { Container.shared.widgetState() }

  @Test("writes valid queue JSON when queue is empty")
  func writesValidQueueJSONWhenQueueEmpty() async throws {
    writer.start()
    let snapshot = try await WidgetHelpers.waitForQueueSnapshot()

    #expect(snapshot.queue.isEmpty)
    #expect(snapshot.queueTotalCount == 0)
    #expect(snapshot.schemaVersion == QueueSnapshot.currentSchemaVersion)
  }

  @Test("includes now-playing data when onDeck is set")
  func includesNowPlayingDataWhenOnDeckIsSet() async throws {
    let episode = try await Create.podcastEpisode()
    let onDeck = OnDeck(podcastEpisode: episode)
    sharedState.$onDeck.new(onDeck)
    sharedState.$playbackStatus.new(.playing)

    writer.start()
    let snapshot = try await WidgetHelpers.waitForNowPlayingSnapshot {
      $0.nowPlaying != nil
    }

    #expect(snapshot.nowPlaying?.episodeID == episode.id.rawValue)
    #expect(snapshot.nowPlaying?.episodeTitle == episode.title)
    #expect(snapshot.nowPlaying?.podcastTitle == episode.podcastTitle)
  }

  @Test("writes playback status to WidgetInfo")
  func writesPlaybackStatusToWidgetInfo() async throws {
    writer.start()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "widgetState.playbackStatus was not updated to .playing" }
    )

    sharedState.$playbackStatus.new(.paused)
    try await Wait.until(
      { self.widgetState.playbackStatus == .paused },
      { "widgetState.playbackStatus was not updated to .paused" }
    )
  }

  @Test("writes loading status to WidgetInfo")
  func writesLoadingStatusToWidgetInfo() async throws {
    writer.start()

    sharedState.$playbackStatus.new(.loading("My Episode"))
    try await Wait.until(
      { self.widgetState.playbackStatus.loadingTitle == "My Episode" },
      { "widgetState.playbackStatus was not updated to loading" }
    )
  }

  @Test("syncs skip intervals to UserDefaults")
  func syncsSkipIntervals() async throws {
    userSettings.$skipForwardInterval.new(45)
    userSettings.$skipBackwardInterval.new(10)
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()

    #expect(widgetState.skipForwardInterval == 45)
    #expect(widgetState.skipBackwardInterval == 10)
  }

  @Test("includes queue items from database")
  func includesQueueItemsFromDatabase() async throws {
    let ep1 = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Queue Ep 1")
    )
    let ep2 = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Queue Ep 2")
    )
    try await queue.unshift([ep2.id, ep1.id])

    writer.start()
    let snapshot = try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 2 }

    #expect(snapshot.queue.count == 2)
    let titles = snapshot.queue.map(\.episodeTitle)
    #expect(titles.contains("Queue Ep 1"))
    #expect(titles.contains("Queue Ep 2"))
  }

  @Test("caps queue at 5 but reports full queueTotalCount")
  func capsQueueAt5ButReportsFullQueueTotalCount() async throws {
    var episodeIDs: [Episode.ID] = []
    for i in 1...10 {
      let ep = try await Create.podcastEpisode(
        try Create.unsavedEpisode(title: "Ep \(i)")
      )
      episodeIDs.append(ep.id)
    }
    try await queue.unshift(episodeIDs)

    writer.start()
    let snapshot = try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 10 }

    #expect(snapshot.queue.count == 5)
  }

  @Test("reloads now-playing timeline periodically while playing")
  func heartbeatReloadsWhilePlaying() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )

    let sleeper = Container.shared.sleeper() as! FakeSleeper

    // Heartbeat registers a sleep for its interval
    try await sleeper.waitForSleepRequests(count: 1)

    // Advancing past the interval causes the heartbeat to loop
    await sleeper.advanceTime(by: .seconds(240))
    try await sleeper.waitForSleepRequests(count: 1)
  }

  @Test("heartbeat stops when paused and restarts when playing resumes")
  func heartbeatStopsAndRestarts() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    let sleeper = Container.shared.sleeper() as! FakeSleeper

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)

    // Pausing cancels the heartbeat
    sharedState.$playbackStatus.new(.paused)
    try await Wait.until(
      { self.widgetState.playbackStatus == .paused },
      { "playbackStatus was not updated to .paused" }
    )
    await sleeper.advanceTime(by: .seconds(240))

    // Resuming playback starts a fresh heartbeat
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(240))
    try await sleeper.waitForSleepRequests(count: 1)
  }

  @Test("heartbeat restarts after transient loading and waiting states")
  func heartbeatRestartsAfterTransientStates() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    let sleeper = Container.shared.sleeper() as! FakeSleeper

    // Loading an episode — no heartbeat
    sharedState.$playbackStatus.new(.loading("My Episode"))
    try await Wait.until(
      { self.widgetState.playbackStatus.loading },
      { "playbackStatus was not updated to .loading" }
    )

    // Playback starts — heartbeat begins
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)

    // Buffering mid-stream — heartbeat stops
    sharedState.$playbackStatus.new(.waiting)
    try await Wait.until(
      { self.widgetState.playbackStatus == .waiting },
      { "playbackStatus was not updated to .waiting" }
    )
    await sleeper.advanceTime(by: .seconds(240))

    // Buffering resolves — heartbeat restarts
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(240))
    try await sleeper.waitForSleepRequests(count: 1)
  }

  // MARK: - Control Center Reloads

  nonisolated private var fakeControlCenter: FakeControlCenter {
    Container.shared.controlCenter() as! FakeControlCenter
  }

  @Test("reloads play/pause control when playback status changes")
  func reloadsPlayPauseControlOnStatusChange() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    fakeControlCenter.reset()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.fakeControlCenter.reloadCount(ofKind: WidgetInfo.playPauseControlKind) >= 1 },
      { "play/pause control was not reloaded on .playing" }
    )

    sharedState.$playbackStatus.new(.paused)
    try await Wait.until(
      { self.fakeControlCenter.reloadCount(ofKind: WidgetInfo.playPauseControlKind) >= 2 },
      { "play/pause control was not reloaded on .paused" }
    )
  }

  @Test("reloads skip forward control when interval changes")
  func reloadsSkipForwardControlOnIntervalChange() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    fakeControlCenter.reset()

    userSettings.$skipForwardInterval.new(45)
    try await Wait.until(
      { self.fakeControlCenter.reloadCount(ofKind: WidgetInfo.skipForwardControlKind) >= 1 },
      { "skip forward control was not reloaded" }
    )
  }

  @Test("reloads skip backward control when interval changes")
  func reloadsSkipBackwardControlOnIntervalChange() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    fakeControlCenter.reset()

    userSettings.$skipBackwardInterval.new(10)
    try await Wait.until(
      { self.fakeControlCenter.reloadCount(ofKind: WidgetInfo.skipBackwardControlKind) >= 1 },
      { "skip backward control was not reloaded" }
    )
  }

  @Test("does not reload skip controls when playback status changes")
  func doesNotReloadSkipControlsOnStatusChange() async throws {
    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    fakeControlCenter.reset()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.fakeControlCenter.reloadCount(ofKind: WidgetInfo.playPauseControlKind) >= 1 },
      { "play/pause control was not reloaded" }
    )

    #expect(fakeControlCenter.reloadCount(ofKind: WidgetInfo.skipForwardControlKind) == 0)
    #expect(fakeControlCenter.reloadCount(ofKind: WidgetInfo.skipBackwardControlKind) == 0)
  }
}
