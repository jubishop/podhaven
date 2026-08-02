// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of WidgetSnapshotWriter tests", .container)
@MainActor class WidgetSnapshotWriterTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.widgetSnapshotWriter) private var writer

  nonisolated private var fileManager: FakeFileManager {
    Container.shared.fileManager() as! FakeFileManager
  }
  nonisolated private var widgetCenter: FakeWidgetCenter {
    Container.shared.widgetCenter() as! FakeWidgetCenter
  }
  nonisolated private var widgetState: WidgetState { Container.shared.widgetState() }

  private let timelineKinds: Set<String> = [
    WidgetInfo.nowPlayingKind,
    WidgetInfo.queueKind,
    WidgetInfo.nowPlayingQueueKind,
    WidgetInfo.lockScreenNowPlayingKind,
  ]

  private func fetchListable(_ episodeID: Episode.ID) async throws -> ListablePodcastEpisode {
    try await repo.db.read { db in
      try ListablePodcastEpisode
        .request(filter: Episode.Columns.id == episodeID)
        .fetchOne(db)!
    }
  }

  private func writeNowPlayingSnapshot(for episode: PodcastEpisode) async throws -> Data {
    let snapshot = NowPlayingSnapshot(
      schemaVersion: NowPlayingSnapshot.currentSchemaVersion,
      nowPlaying: NowPlayingSnapshot.NowPlaying(
        episodeID: episode.id.rawValue,
        episodeTitle: episode.title,
        podcastTitle: episode.podcastTitle,
        pubDateTimestamp: episode.pubDate.timeIntervalSince1970,
        durationSeconds: episode.duration.seconds,
        artworkBase64: nil
      ),
      updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let data = try JSONEncoder().encode(snapshot)
    try await fileManager.writeData(data, to: WidgetInfo.nowPlayingSnapshotURL)
    return data
  }

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
    let onDeck = OnDeck(from: episode)
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

  @Test("preserves snapshot while persisted episode awaits restoration")
  func preservesSnapshotWhilePersistedEpisodeAwaitsRestoration() async throws {
    let episode = try await Create.podcastEpisode()
    sharedState.currentEpisodeID = episode.id

    let snapshotData = try await writeNowPlayingSnapshot(for: episode)

    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()

    let preservedData = try await fileManager.readData(from: WidgetInfo.nowPlayingSnapshotURL)
    #expect(preservedData == snapshotData)
  }

  @Test("invalidates preserved snapshot when persisted episode is cleared")
  func invalidatesPreservedSnapshotWhenPersistedEpisodeIsCleared() async throws {
    let episode = try await Create.podcastEpisode()
    sharedState.currentEpisodeID = episode.id
    let snapshotData = try await writeNowPlayingSnapshot(for: episode)

    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()

    stateManager.clearOnDeck()

    let invalidated = try await WidgetHelpers.waitForNowPlayingSnapshot {
      $0.nowPlaying == nil
    }
    let invalidatedData = try await fileManager.readData(from: WidgetInfo.nowPlayingSnapshotURL)

    #expect(invalidated.nowPlaying == nil)
    #expect(invalidatedData != snapshotData)
    try await Wait.until(
      { self.widgetCenter.reloadCount(ofKind: WidgetInfo.nowPlayingKind) > 0 },
      { "Now-playing widgets were not reloaded after persisted episode invalidation" }
    )
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

  @Test("includes queue items from shared state")
  func includesQueueItemsFromSharedState() async throws {
    let pe1 = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Queue Ep 1")
    )
    let pe2 = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Queue Ep 2")
    )
    let ep1 = try await fetchListable(pe1.id)
    let ep2 = try await fetchListable(pe2.id)
    sharedState.$queuedPodcastEpisodes.new([ep1, ep2])

    writer.start()
    let snapshot = try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 2 }

    #expect(snapshot.queue.count == 2)
    let titles = snapshot.queue.map(\.episodeTitle)
    #expect(titles.contains("Queue Ep 1"))
    #expect(titles.contains("Queue Ep 2"))
  }

  @Test("skips queue snapshot write when only non-widget episode fields change")
  func skipsQueueSnapshotWriteWhenOnlyNonWidgetFieldsChange() async throws {
    let pe = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Widget Ep")
    )
    let ep = try await fetchListable(pe.id)
    sharedState.$queuedPodcastEpisodes.new([ep])

    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 1 }

    let fakeFileManager = Container.shared.fileManager() as! FakeFileManager
    let initialData = try await fakeFileManager.readData(from: WidgetInfo.queueSnapshotURL)

    // Update the episode in DB with a different currentTime (non-widget field),
    // then re-fetch as ListablePodcastEpisode.
    try await repo.updateCurrentTime(pe.id, currentTime: CMTime(seconds: 99, preferredTimescale: 1))
    let modifiedEp = try await fetchListable(pe.id)
    sharedState.$queuedPodcastEpisodes.new([modifiedEp])

    // Observe a playback status change to confirm the event loop has processed
    // all pending stream emissions, including the queue change above.
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.widgetState.playbackStatus == .playing },
      { "playbackStatus was not updated to .playing" }
    )

    let currentData = try await fakeFileManager.readData(from: WidgetInfo.queueSnapshotURL)
    #expect(initialData == currentData)
  }

  @Test("caps queue at 5 but reports full queueTotalCount")
  func capsQueueAt5ButReportsFullQueueTotalCount() async throws {
    var episodes: [ListablePodcastEpisode] = []
    for i in 1...10 {
      let pe = try await Create.podcastEpisode(
        try Create.unsavedEpisode(title: "Ep \(i)")
      )
      episodes.append(try await fetchListable(pe.id))
    }
    sharedState.$queuedPodcastEpisodes.new(episodes)

    writer.start()
    let snapshot = try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 10 }

    #expect(snapshot.queue.count == 5)
  }

  @Test("upgrade writes initial snapshots before exactly one reload-all")
  func upgradeWritesInitialSnapshotsBeforeReloadAll() async throws {
    let nowPlayingEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Current Episode")
    )
    let queuedEpisode = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Current Queue Episode")
    )
    sharedState.$onDeck.new(OnDeck(from: nowPlayingEpisode))
    sharedState.$queuedPodcastEpisodes.new([try await fetchListable(queuedEpisode.id)])
    widgetState.lastUpgradeRecoveryBuild = "previous-build"
    Container.shared.widgetState.reset()

    writer.start()

    try await Wait.until(
      { self.widgetCenter.reloadAllCount() == 1 },
      { "Widget timelines were not reloaded together after the build transition" }
    )
    let nowPlayingSnapshot = try await WidgetHelpers.waitForNowPlayingSnapshot()
    let queueSnapshot = try await WidgetHelpers.waitForQueueSnapshot()

    #expect(widgetCenter.reloadAllCount() == 1)
    #expect(widgetCenter.everyReloadAllHadInitialSnapshots())
    #expect(nowPlayingSnapshot.nowPlaying?.episodeID == nowPlayingEpisode.id.rawValue)
    #expect(queueSnapshot.queue.first?.episodeID == queuedEpisode.id.rawValue)
    #expect(timelineKinds.allSatisfy { widgetCenter.reloadCount(ofKind: $0) == 0 })
    #expect(widgetState.lastUpgradeRecoveryBuild == AppInfo.buildNumber)
  }

  @Test("first tracked build performs one reload-all")
  func firstTrackedBuildPerformsReloadAll() async throws {
    writer.start()

    try await Wait.until(
      { self.widgetCenter.reloadAllCount() == 1 },
      { "The first build with upgrade tracking did not request reload-all" }
    )

    #expect(widgetCenter.reloadAllCount() == 1)
    #expect(widgetCenter.everyReloadAllHadInitialSnapshots())
    #expect(timelineKinds.allSatisfy { widgetCenter.reloadCount(ofKind: $0) == 0 })
    #expect(widgetState.lastUpgradeRecoveryBuild == AppInfo.buildNumber)
  }

  @Test("same-build startup coalesces targeted timeline reloads")
  func sameBuildStartupCoalescesTargetedReloads() async throws {
    widgetState.lastUpgradeRecoveryBuild = AppInfo.buildNumber
    Container.shared.widgetState.reset()

    writer.start()
    try await WidgetHelpers.waitForQueueSnapshot()
    try await Wait.until(
      { self.timelineKinds.allSatisfy { self.widgetCenter.reloadCount(ofKind: $0) >= 1 } },
      { "Startup did not request every targeted widget timeline" }
    )

    #expect(widgetCenter.reloadAllCount() == 0)
    #expect(widgetCenter.placedWidgetKindsRequestCount() == 1)
    for kind in timelineKinds {
      #expect(widgetCenter.reloadCount(ofKind: kind) == 1)
    }
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

  // MARK: - Widget Timeline Reloads

  nonisolated private var fakeWidgetCenter: FakeWidgetCenter {
    Container.shared.widgetCenter() as! FakeWidgetCenter
  }

  @Test(
    "reloads the now-playing & up-next widget on now-playing, playback, queue, and skip changes"
  )
  func reloadsNowPlayingQueueWidget() async throws {
    let kind = WidgetInfo.nowPlayingQueueKind

    let initialEpisode = try await Create.podcastEpisode()
    sharedState.$onDeck.new(OnDeck(from: initialEpisode))
    writer.start()
    try await WidgetHelpers.waitForNowPlayingSnapshot { $0.nowPlaying != nil }
    try await Wait.until(
      { self.fakeWidgetCenter.reloadAllCount() == 1 },
      { "Initial widget recovery did not finish" }
    )

    // A later episode change keeps the combined widget reload targeted.
    fakeWidgetCenter.reset()
    let replacementEpisode = try await Create.podcastEpisode()
    sharedState.$onDeck.new(OnDeck(from: replacementEpisode))
    try await WidgetHelpers.waitForNowPlayingSnapshot {
      $0.nowPlaying?.episodeID == replacementEpisode.id.rawValue
    }
    try await Wait.until(
      { self.fakeWidgetCenter.reloadCount(ofKind: kind) >= 1 },
      { "combined widget was not reloaded on now-playing change" }
    )

    // Playback status (play/pause) reloads the combined widget.
    fakeWidgetCenter.reset()
    sharedState.$playbackStatus.new(.playing)
    try await Wait.until(
      { self.fakeWidgetCenter.reloadCount(ofKind: kind) >= 1 },
      { "combined widget was not reloaded on playback-status change" }
    )

    // Queue change reloads the combined widget (up-next data).
    fakeWidgetCenter.reset()
    let queued = try await Create.podcastEpisode(
      try Create.unsavedEpisode(title: "Queued Ep")
    )
    let listable = try await fetchListable(queued.id)
    sharedState.$queuedPodcastEpisodes.new([listable])
    try await WidgetHelpers.waitForQueueSnapshot { $0.queueTotalCount == 1 }
    try await Wait.until(
      { self.fakeWidgetCenter.reloadCount(ofKind: kind) >= 1 },
      { "combined widget was not reloaded on queue change" }
    )

    // Skip-interval change reloads the combined widget (header transport controls).
    fakeWidgetCenter.reset()
    userSettings.$skipForwardInterval.new(45)
    try await Wait.until(
      { self.fakeWidgetCenter.reloadCount(ofKind: kind) >= 1 },
      { "combined widget was not reloaded on skip-interval change" }
    )
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
