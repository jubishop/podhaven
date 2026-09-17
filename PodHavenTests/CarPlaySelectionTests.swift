// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of CarPlay selection tests", .container)
@MainActor struct CarPlaySelectionTests {
  private func connect(_ episodes: [PodcastEpisode]) async throws -> (
    CarPlayCoordinator, FakeCarPlayInterfaceController, [CPListItem]
  ) {
    await Container.shared.appLauncher().prepareForPlayback()
    for episode in episodes { try await Container.shared.queue().append(episode.id) }
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let list = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until(
      { await list.itemCount == episodes.count },
      { "Missing selectable queue rows" }
    )
    return (
      coordinator, controller, list.sections.flatMap(\.items).compactMap { $0 as? CPListItem }
    )
  }

  @Test("duplicate taps share lookup and playback and finish both callbacks once")
  func duplicates() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let count = ThreadSafe(0)
    let row = rows[0]
    let handler = try #require(row.handler)
    handler(row) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    handler(row) { count { $0 += 1 } }
    #expect(count() == 0)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    try await Wait.until({ count() == 2 }, { "Both callbacks must complete" })
    #expect(controller.pushed.count == 1)
    #expect(controller.topTemplate === CPNowPlayingTemplate.shared)
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 1
    )
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
    #expect(controller.alerts.isEmpty)
  }

  @Test("newer selection wins when the old repository lookup finishes last")
  func reversedLookup() async throws {
    let first = try await Create.podcastEpisode()
    let second = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([first, second])
    defer { coordinator.disconnect(controller) }
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let old = ThreadSafe(0)
    let latest = ThreadSafe(0)
    rows[0].handler?(rows[0]) { old { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    rows[1].handler?(rows[1]) { latest { $0 += 1 } }
    try await Wait.until({ latest() == 1 }, { "Newer selection must finish" })
    #expect(old() == 1)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: first.episode.mediaURL)
        == 0
    )
    #expect(Container.shared.sharedState().currentEpisodeID == second.id)
    #expect(controller.pushed.count == 1)
    #expect(controller.alerts.isEmpty)
  }

  @Test("a newer phone play request wins over a pending CarPlay lookup")
  func phoneDuringLookup() async throws {
    let first = try await Create.podcastEpisode()
    let phone = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([first])
    defer { coordinator.disconnect(controller) }
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    try await Container.shared.playManager().play(phone)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    try await Wait.until({ count() == 1 }, { "Superseded callback must complete" })
    #expect(Container.shared.sharedState().currentEpisodeID == phone.id)
    #expect(controller.pushed.isEmpty)
    #expect(controller.alerts.isEmpty)
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: first.episode.mediaURL)
        == 0
    )
  }

  @Test("remote toggle supersedes a pending CarPlay lookup", arguments: [false, true])
  func toggleDuringLookup(playing: Bool) async throws {
    let selected = try await Create.podcastEpisode()
    let current = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([selected])
    defer { coordinator.disconnect(controller) }
    let player = Container.shared.playManager()
    try await player.load(current)
    if playing { await player.play() }
    try await PlayHelpers.waitFor(playing ? .playing : .paused)
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    do {
      Container.shared.commandCenterStream().continuation.yield(.togglePlayPause)
      try await PlayHelpers.waitFor(playing ? .paused : .playing)
      try await Wait.until(
        { count() == 1 },
        { "Remote toggle must promptly complete the superseded CarPlay callback" }
      )
    } catch {
      await repo.resumeAllPodcastEpisodeFetchSuspensions()
      throw error
    }
    #expect(Container.shared.sharedState().currentEpisodeID == current.id)
    #expect(controller.pushed.isEmpty)
    #expect(controller.alerts.isEmpty)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: selected.episode.mediaURL)
        == 0
    )
  }

  @Test("disconnect completes pending lookup without playing or navigating on reconnect")
  func disconnectLookup() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, oldController, rows) = try await connect([episode])
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let count = ThreadSafe(0)
    let oldHandler = try #require(rows[0].handler)
    oldHandler(rows[0]) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    coordinator.disconnect(oldController)
    #expect(count() == 1)
    #expect(rows[0].handler == nil)
    let replacement = FakeCarPlayInterfaceController()
    coordinator.connect(replacement)
    replacement.completions[0](true, nil)
    defer { coordinator.disconnect(replacement) }
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 0
    )
    #expect(oldController.pushed.isEmpty)
    #expect(replacement.pushed.isEmpty)
  }

  @Test("deleted selection completes with a native error")
  func deletion() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    let row = rows[0]
    let handler = try #require(row.handler)
    _ = try await Container.shared.repo().deletePodcast(episode.podcast.id)
    let count = ThreadSafe(0)
    handler(row) { count { $0 += 1 } }
    try await Wait.until({ count() == 1 }, { "Deleted selection must complete" })
    #expect(controller.alerts.count == 1)
    #expect(controller.pushed.isEmpty)
  }

  @Test(
    "failed media and refused audio activation complete with a native error",
    arguments: [false, true]
  )
  func loadFailure(refuseAudio: Bool) async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    if refuseAudio {
      Container.shared.fakeAudioSession().configureError(URLError(.cannotLoadFromNetwork))
    } else {
      await Container.shared.fakeEpisodeAssetLoader()
        .respond(to: episode.episode.mediaURL, error: URLError(.cannotLoadFromNetwork))
    }
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await Wait.until({ count() == 1 }, { "Failed selection must complete" })
    #expect(controller.alerts.count == 1)
    #expect(controller.pushed.isEmpty)
  }

  @Test("stalled lookup reaches a bounded retry state and ignores late success")
  func deadline() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    try await sleeper.waitForSleepRequests(for: .seconds(30))
    await sleeper.advanceTime(by: .seconds(30))
    try await Wait.until({ count() == 1 }, { "Deadline must finish the spinner" })
    #expect(controller.alerts.count == 1)
    #expect(rows[0].handler != nil)
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 0
    )
    #expect(controller.pushed.isEmpty)
  }

  @Test("disconnect after playback handoff leaves shared playback running")
  func disconnectLoad() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    let gate = AsyncSemaphore(value: 0)
    let entered = ThreadSafe(false)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: episode.episode.mediaURL) { _ in
        entered(true)
        await gate.wait()
        return (true, .seconds(60))
      }
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await Wait.until({ entered() }, { "Load must start" })
    coordinator.disconnect(controller)
    #expect(count() == 1)
    gate.signal()
    try await PlayHelpers.waitFor(.playing)
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
    #expect(controller.pushed.isEmpty)
    #expect(controller.alerts.isEmpty)
    #expect(count() == 1)
  }
  @Test("a callback retained by the system after disconnect cannot start playback")
  func retainedHandlerAfterDisconnect() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    let handler = try #require(rows[0].handler)
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let count = ThreadSafe(0)
    handler(rows[0]) { count { $0 += 1 } }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    coordinator.disconnect(controller)
    handler(rows[0]) { count { $0 += 1 } }
    try await Wait.until({ count() == 2 }, { "Disconnected callbacks must finish" })
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 0
    )
    #expect(Container.shared.sharedState().currentEpisodeID == nil)
  }
  @Test("a new phone request promptly completes the older CarPlay spinner during a stalled load")
  func phoneDuringLoad() async throws {
    let episode = try await Create.podcastEpisode()
    let phone = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    let gate = AsyncSemaphore(value: 0)
    defer { gate.signal() }
    let entered = ThreadSafe(false)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: episode.episode.mediaURL) { _ in
        entered(true)
        await gate.wait()
        throw URLError(.cannotLoadFromNetwork)
      }
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await Wait.until({ entered() }, { "Load must start" })
    try await Container.shared.playManager().play(phone)
    try await Wait.until(
      { count() == 1 },
      { "New phone request must promptly finish the old spinner" }
    )
    gate.signal()
    #expect(Container.shared.sharedState().currentEpisodeID == phone.id)
    #expect(controller.pushed.isEmpty)
    #expect(controller.alerts.isEmpty)
  }

  @Test("a stalled accepted load ends its spinner at the deadline without stale navigation")
  func stalledMediaDeadline() async throws {
    let episode = try await Create.podcastEpisode()
    let (coordinator, controller, rows) = try await connect([episode])
    defer { coordinator.disconnect(controller) }
    let gate = AsyncSemaphore(value: 0)
    defer { gate.signal() }
    let entered = ThreadSafe(false)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: episode.episode.mediaURL) { _ in
        entered(true)
        await gate.wait()
        return (true, .seconds(60))
      }
    let count = ThreadSafe(0)
    rows[0].handler?(rows[0]) { count { $0 += 1 } }
    try await Wait.until({ entered() }, { "Media loading must start" })
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    try await sleeper.waitForSleepRequests(for: .seconds(30))
    await sleeper.advanceTime(by: .seconds(30))
    try await Wait.until({ count() == 1 }, { "Stalled media must not leave a permanent spinner" })
    #expect(controller.alerts.count == 1)
    gate.signal()
    try await PlayHelpers.waitFor(.playing)
    #expect(controller.pushed.isEmpty)
    #expect(count() == 1)
  }

}
