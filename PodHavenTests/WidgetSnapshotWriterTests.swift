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

  private var fakeFileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }

  private var sleeper: FakeSleeper {
    Container.shared.sleeper() as! FakeSleeper
  }

  // MARK: - Helpers

  private func waitForSnapshot() async throws {
    try await sleeper.waitForSleepRequests(count: 1)
    await sleeper.advanceTime(by: .milliseconds(100))
    try await Wait.until(
      { [fakeFileManager] in fakeFileManager.fileExists(at: WidgetInfo.snapshotURL) },
      { "Snapshot file was never written" }
    )
  }

  private func decodeSnapshot() async throws -> WidgetSnapshot {
    let data = try await fakeFileManager.readData(from: WidgetInfo.snapshotURL)
    return try JSONDecoder().decode(WidgetSnapshot.self, from: data)
  }

  // MARK: - Tests

  @Test("writes valid JSON when nothing is playing and queue is empty")
  func writesValidJSONWhenNothingPlayingAndQueueEmpty() async throws {
    writer.start()
    try await waitForSnapshot()

    let snapshot = try await decodeSnapshot()
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
    try await waitForSnapshot()

    let snapshot = try await decodeSnapshot()
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
    try await waitForSnapshot()

    let snapshot = try await decodeSnapshot()
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
    try await waitForSnapshot()

    let snapshot = try await decodeSnapshot()
    #expect(snapshot.queue.count == 2)
    #expect(snapshot.queueTotalCount == 2)
    let titles = snapshot.queue.map(\.episodeTitle)
    #expect(titles.contains("Queue Ep 1"))
    #expect(titles.contains("Queue Ep 2"))
  }

  @Test("caps queue at 8 but reports full queueTotalCount")
  func capsQueueAt8ButReportsFullQueueTotalCount() async throws {
    var episodeIDs: [Episode.ID] = []
    for i in 1...10 {
      let ep = try await Create.podcastEpisode(
        try Create.unsavedEpisode(title: "Ep \(i)")
      )
      episodeIDs.append(ep.id)
    }
    try await queue.unshift(episodeIDs)

    writer.start()
    try await waitForSnapshot()

    let snapshot = try await decodeSnapshot()
    #expect(snapshot.queue.count == 8)
    #expect(snapshot.queueTotalCount == 10)
  }
}
