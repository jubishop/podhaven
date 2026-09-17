// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of CarPlay playback tests", .container)
@MainActor struct CarPlayPlaybackTests {
  @Test("Up Next projects the durable queue without playing")
  func queueProjection() async throws {
    let first = try await Create.podcastEpisode()
    let second = try await Create.podcastEpisode()
    try await Container.shared.queue().append(first.id)
    try await Container.shared.queue().append(second.id)
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let list = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until(
      { await list.itemCount == 2 },
      { "CarPlay must project the queue into native selectable rows" }
    )
    let rows = list.sections.flatMap(\.items)
    #expect(rows.map(\.text) == [first.title, second.title])
    #expect(
      Container.shared.sharedState().queuedPodcastEpisodes.map(\.id) == [first.id, second.id]
    )
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
    #expect(controller.roots.count == 1)
  }

  @Test("current paused episode remains reachable without resuming")
  func pausedCurrent() async throws {
    let episode = try await Create.podcastEpisode(Create.unsavedEpisode(currentTime: .seconds(12)))
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().load(episode)
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let list = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until({ await list.itemCount == 1 }, { "Current episode must remain reachable" })
    let item = try #require(list.sections.first?.items.first as? CPListItem)
    let handler = try #require(item.handler)
    let completions = ThreadSafe(0)
    handler(item) { completions { $0 += 1 } }
    try await Wait.until({ completions() == 1 }, { "Selection did not complete" })
    #expect(!Container.shared.sharedState().playbackStatus.playing)
    #expect(Container.shared.sharedState().onDeck?.currentTime == .seconds(12))
    #expect(Container.shared.sharedState().queuedPodcastEpisodes.isEmpty)
  }
}
