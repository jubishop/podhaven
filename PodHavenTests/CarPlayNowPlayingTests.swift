// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of CarPlay Now Playing tests", .container)
@MainActor struct CarPlayNowPlayingTests {
  @Test("Now Playing uses shared commands, returns to Up Next, and releases connection handlers")
  func controlsAndCleanup() async throws {
    let action = ThreadSafe<(@MainActor () -> Void)?>(nil)
    Container.shared.carPlayRateButton.context(.test) {
      { handler in
        action(handler)
        return CPNowPlayingPlaybackRateButton { _ in handler() }
      }
    }
    PlayHelpers.setupCommandHandling()
    let episode = try await Create.podcastEpisode()
    await Container.shared.appLauncher().prepareForPlayback()
    try await Container.shared.playManager().load(episode)
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    let nowPlaying = Container.shared.carPlayNowPlaying() as! FakeCarPlayNowPlaying
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let queue = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until({ await queue.itemCount == 1 }, { "Current episode must appear" })
    let row = try #require(queue.sections.first?.items.first as? CPListItem)
    let handler = try #require(row.handler)
    let count = ThreadSafe(0)
    handler(row) { count { $0 += 1 } }
    try await Wait.until({ count() == 1 }, { "Current selection must open Now Playing" })
    #expect(controller.pushed.count == 1)
    handler(row) { count { $0 += 1 } }
    try await Wait.until({ count() == 2 }, { "Second selection must complete" })
    #expect(controller.pushed.count == 1)
    #expect(nowPlaying.buttons.first is CPNowPlayingPlaybackRateButton)
    #expect(nowPlaying.isUpNextButtonEnabled)
    #expect(!nowPlaying.isAlbumArtistButtonEnabled)
    #expect(nowPlaying.observers.count == 1)
    let originalRate = Container.shared.sharedState().playRate
    let changeRate = try #require(action())
    changeRate()
    try await Wait.until(
      { Container.shared.sharedState().playRate > originalRate },
      { "Rate button must use shared command handling" }
    )
    #expect(!Container.shared.sharedState().playbackStatus.playing)
    let queued = try await Create.podcastEpisode()
    try await Container.shared.queue().append(queued.id)
    try await Wait.until({ await queue.itemCount == 2 }, { "Queue must update behind Now Playing" })
    #expect(controller.topTemplate === CPNowPlayingTemplate.shared)
    #expect(controller.roots.count == 1)
    coordinator.nowPlayingTemplateUpNextButtonTapped(CPNowPlayingTemplate.shared)
    #expect(controller.topTemplate === root)
    #expect(root.selectedTemplate === queue)
    coordinator.disconnect(controller)
    #expect(nowPlaying.observers.isEmpty)
    #expect(nowPlaying.buttons.isEmpty)
    #expect(!nowPlaying.isUpNextButtonEnabled)
    let rate = Container.shared.sharedState().playRate
    changeRate()
    #expect(Container.shared.sharedState().playRate == rate)
  }

  @Test("runtime list restrictions update the existing root and remove page controls")
  func runtimeRestrictions() async throws {
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 4, sections: 2) }
    }
    var session: CPSessionConfiguration?
    Container.shared.carPlaySession.context(.test) {
      { delegate in
        let configuration = CPSessionConfiguration(delegate: delegate)
        session = configuration
        return configuration
      }
    }
    for _ in 0..<8 {
      let episode = try await Create.podcastEpisode()
      try await Container.shared.queue().append(episode.id)
    }
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    defer { coordinator.disconnect(controller) }
    controller.completions[0](true, nil)
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let queue = try #require(root.templates.first as? CPListTemplate)
    try await Wait.until({ await queue.itemCount == 3 }, { "Paged queue must appear" })
    let configuration = try #require(session)
    coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(queue.itemCount == 4)
    #expect(queue.sections.flatMap(\.items).allSatisfy { $0.text != "Next page" })
    Container.shared.carPlayListLimits.context(.test) {
      { CarPlayListLimits(items: 2, sections: 1) }
    }
    coordinator.sessionConfiguration(configuration, limitedUserInterfacesChanged: .lists)
    #expect(queue.itemCount == 2)
    #expect(queue.sections.count == 1)
    #expect(controller.roots.count == 1)
  }
}
