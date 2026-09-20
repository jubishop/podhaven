// Copyright Justin Bishop, 2026

import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Intents
import Testing

@testable import PodHaven

@Suite("of Siri CarPlay presentation", .container)
@MainActor struct SiriCarPlayTests {
  @Test(
    "only the Up Next root offers the native assistant when authorized",
    arguments: [false, true]
  )
  func assistantAvailability(authorized: Bool) throws {
    Container.shared.siriAuthorized.context(.test) { { authorized } }
    let root = CarPlayRootTemplate.make(state: .ready, retry: {})
    let lists = root.templates.compactMap { $0 as? CPListTemplate }
    #expect(lists.count == 3)
    #expect((lists[0].assistantCellConfiguration != nil) == authorized)
    #expect(lists[1].assistantCellConfiguration == nil)
    #expect(lists[2].assistantCellConfiguration == nil)
    if let assistant = lists[0].assistantCellConfiguration {
      #expect(assistant.assistantAction == .playMedia)
    }
  }

  @Test("a disconnected request cannot navigate after reconnection")
  func disconnect() async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    Container.shared.appDB().startSiriCatalog(file)
    let episode = try await Create.podcastEpisode(Create.unsavedEpisode(title: "Pending Siri"))
    await Container.shared.appLauncher().prepareForPlayback()
    let coordinator = Container.shared.carPlayCoordinator()
    let old = FakeCarPlayInterfaceController()
    coordinator.connect(old)
    old.completions[0](true, nil)
    let repo = Container.shared.repo() as! FakeRepo
    repo.pendingPodcastEpisodeFetchSuspend(true)
    let codes = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Pending Siri")) { response in
        codes { $0.append(response.code.rawValue) }
      }
    try await repo.waitForPodcastEpisodeFetchSuspended()
    coordinator.disconnect(old)
    let new = FakeCarPlayInterfaceController()
    coordinator.connect(new)
    new.completions[0](true, nil)
    defer { coordinator.disconnect(new) }
    await repo.resumeAllPodcastEpisodeFetchSuspensions()
    try await Wait.until({ !codes().isEmpty }, { "Siri callback never completed" })
    #expect(codes() == [INPlayMediaIntentResponseCode.success.rawValue])
    #expect(old.pushed.isEmpty)
    #expect(new.pushed.isEmpty)
    #expect(Container.shared.sharedState().currentEpisodeID == episode.id)
  }

  @Test("successful Siri playback presents Now Playing through the connected coordinator")
  func connectedPlayback() async throws {
    let file = Container.shared.siriCatalogFile()
    defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
    Container.shared.appDB().startSiriCatalog(file)
    _ = try await Create.podcastEpisode(Create.unsavedEpisode(title: "Connected Siri"))
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    defer { coordinator.disconnect(controller) }
    let codes = ThreadSafe<[Int]>([])
    Container.shared.siriPlayback().handler
      .handle(intent: SiriTestIntent.named("Connected Siri")) { response in
        codes { $0.append(response.code.rawValue) }
      }
    try await Wait.until({ !codes().isEmpty }, { "Siri callback never completed" })
    #expect(codes() == [INPlayMediaIntentResponseCode.success.rawValue])
    #expect(controller.topTemplate === CPNowPlayingTemplate.shared)
    #expect(controller.pushed.count == 1)
  }

  @Test("revoked authorization removes the assistant from the current connection")
  func revokedAuthorization() throws {
    let authorization = ThreadSafe(true)
    Container.shared.siriAuthorized.context(.test) { { authorization() } }
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](true, nil)
    defer { coordinator.disconnect(controller) }
    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let queue = try #require(root.templates.first as? CPListTemplate)
    #expect(queue.assistantCellConfiguration != nil)
    authorization(false)
    coordinator.templateDidAppear(queue, animated: false)
    #expect(queue.assistantCellConfiguration == nil)
  }
}
