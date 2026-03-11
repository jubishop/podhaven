// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of WidgetSnapshotWriter tests", .container)
@MainActor class WidgetSnapshotWriterTests {
  @DynamicInjected(\.widgetSnapshotWriter) private var writer
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.queue) private var queue

  @Test("writes valid JSON when nothing is playing and queue is empty")
  func writesValidJSONWhenNothingPlayingAndQueueEmpty() async throws {
    writer.start()
    try await WidgetHelpers.waitForSnapshot()

    let snapshot = try await WidgetHelpers.decodeSnapshot()
    #expect(snapshot.nowPlaying == nil)
    #expect(snapshot.queue.isEmpty)
    #expect(snapshot.queueTotalCount == 0)
    #expect(snapshot.schemaVersion == WidgetSnapshot.currentSchemaVersion)
  }

  @Test("includes now-playing data when onDeck is set")
  func includesNowPlayingDataWhenOnDeckIsSet() async throws {
    let episode = try await Create.podcastEpisode()
    let onDeck = OnDeck(podcastEpisode: episode)
    sharedState.$onDeck.new(onDeck)
    sharedState.$playbackStatus.new(.playing)

    writer.start()
    try await WidgetHelpers.waitForSnapshot()

    let snapshot = try await WidgetHelpers.decodeSnapshot()
    #expect(snapshot.nowPlaying?.episodeID == episode.id.rawValue)
    #expect(snapshot.nowPlaying?.episodeTitle == episode.title)
    #expect(snapshot.nowPlaying?.podcastTitle == episode.podcastTitle)
  }

  @Test("writes playback status to WidgetInfo")
  func writesPlaybackStatusToWidgetInfo() async throws {
    writer.start()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
      { "WidgetInfo.playbackStatus was not updated to .playing" }
    )

    sharedState.$playbackStatus.new(.paused)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .paused },
      { "WidgetInfo.playbackStatus was not updated to .paused" }
    )
  }

  @Test("writes loading status to WidgetInfo")
  func writesLoadingStatusToWidgetInfo() async throws {
    writer.start()

    sharedState.$playbackStatus.new(.loading("My Episode"))
    try await Wait.until(
      { WidgetInfo.playbackStatus.loadingTitle == "My Episode" },
      { "WidgetInfo.playbackStatus was not updated to loading" }
    )
  }

  @Test("includes user settings")
  func includesUserSettings() async throws {
    userSettings.$skipForwardInterval.new(45)
    userSettings.$skipBackwardInterval.new(10)
    writer.start()
    try await WidgetHelpers.waitForSnapshot()

    let snapshot = try await WidgetHelpers.decodeSnapshot()
    #expect(snapshot.skipForwardInterval == 45)
    #expect(snapshot.skipBackwardInterval == 10)
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
    let snapshot = try await WidgetHelpers.waitForSnapshot { $0.queueTotalCount == 2 }

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
    let snapshot = try await WidgetHelpers.waitForSnapshot { $0.queueTotalCount == 10 }

    #expect(snapshot.queue.count == 5)
  }

  @Test("reloads now-playing timeline periodically while playing")
  func heartbeatReloadsWhilePlaying() async throws {
    writer.start()
    try await WidgetHelpers.waitForSnapshot()

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
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
    try await WidgetHelpers.waitForSnapshot()
    let sleeper = Container.shared.sleeper() as! FakeSleeper

    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)

    // Pausing cancels the heartbeat
    sharedState.$playbackStatus.new(.paused)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .paused },
      { "playbackStatus was not updated to .paused" }
    )
    await sleeper.advanceTime(by: .seconds(240))

    // Resuming playback starts a fresh heartbeat
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(240))
    try await sleeper.waitForSleepRequests(count: 1)
  }

  @Test("heartbeat restarts after transient loading and waiting states")
  func heartbeatRestartsAfterTransientStates() async throws {
    writer.start()
    try await WidgetHelpers.waitForSnapshot()
    let sleeper = Container.shared.sleeper() as! FakeSleeper

    // Loading an episode — no heartbeat
    sharedState.$playbackStatus.new(.loading("My Episode"))
    try await Wait.until(
      { WidgetInfo.playbackStatus.loading },
      { "playbackStatus was not updated to .loading" }
    )

    // Playback starts — heartbeat begins
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)

    // Buffering mid-stream — heartbeat stops
    sharedState.$playbackStatus.new(.waiting)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .waiting },
      { "playbackStatus was not updated to .waiting" }
    )
    await sleeper.advanceTime(by: .seconds(240))

    // Buffering resolves — heartbeat restarts
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { WidgetInfo.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .seconds(240))
    try await sleeper.waitForSleepRequests(count: 1)
  }
}
