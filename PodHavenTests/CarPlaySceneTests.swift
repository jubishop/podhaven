// Copyright Justin Bishop, 2026

import AVFoundation
import CarPlay
import FactoryKit
import FactoryTesting
import Foundation
import Semaphore
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of CarPlay scene tests", .container)
@MainActor struct CarPlaySceneTests {
  @Test("the built app registers the audio CarPlay scene")
  func builtSceneManifest() throws {
    let manifest = try #require(
      Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any]
    )
    let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
    #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true)
    let carPlay = try #require(
      configurations["CPTemplateApplicationSceneSessionRoleApplication"] as? [[String: Any]]
    )
    #expect(carPlay.count == 1)
    #expect(carPlay.first?["UISceneClassName"] as? String == "CPTemplateApplicationScene")
    let delegateName = try #require(carPlay.first?["UISceneDelegateClassName"] as? String)
    #expect(NSClassFromString(delegateName) != nil)
    let delegate = CarPlaySceneDelegate()
    #expect(
      delegate.responds(
        to: NSSelectorFromString("templateApplicationScene:didConnectInterfaceController:")
      )
    )
    #expect(
      delegate.responds(
        to: NSSelectorFromString("templateApplicationScene:didDisconnectInterfaceController:")
      )
    )
  }

  @Test("cold connection installs three native tabs without restoring media or foregrounding")
  func coldConnection() async throws {
    let episode = try await Create.podcastEpisode()
    episode.id.store(to: Container.shared.standardDefaults(), forKey: "currentEpisodeID")
    let state = Container.shared.sharedState()
    let phonePhase = state.scenePhase
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    defer { coordinator.disconnect(controller) }

    coordinator.connect(controller)

    let root = try #require(controller.roots.first as? CPTabBarTemplate)
    let lists = root.templates.compactMap { $0 as? CPListTemplate }
    #expect(lists.count == 3)
    #expect(lists.map(\.title) == ["Up Next", "Episodes", "Podcasts"])
    #expect(lists.map(\.tabTitle) == ["Up Next", "Episodes", "Podcasts"])
    #expect(lists.allSatisfy { $0.tabImage != nil && $0.sections.isEmpty })
    #expect(
      lists.allSatisfy {
        !$0.emptyViewTitleVariants.isEmpty && !$0.emptyViewSubtitleVariants.isEmpty
      }
    )
    #expect(state.scenePhase == phonePhase)
    #expect(state.currentEpisodeID == episode.id)
    #expect(state.onDeck == nil)
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 0
    )
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
    #expect((Container.shared.avPlayer() as! FakeAVPlayer).current == nil)

    let observatory = Container.shared.observatory() as! FakeObservatory
    try await Wait.until(
      { observatory.allCallsInOrder.count >= 3 },
      { "Shared data observers did not start" }
    )
    #expect(
      observatory.allCallsInOrder.map(\.methodName).sorted() == [
        "queuedPodcastEpisodes", "smartLists", "tags",
      ]
    )
    #expect(controller.roots.count == 1)
  }

  @Test(
    "slow or failed saved-media restoration does not block reconnect",
    arguments: [false, true]
  )
  func pendingMediaRestoration(fails: Bool) async throws {
    let episode = try await Create.podcastEpisode()
    episode.id.store(to: Container.shared.standardDefaults(), forKey: "currentEpisodeID")
    let entered = ThreadSafe(false)
    let gate = AsyncSemaphore(value: 0)
    await Container.shared.fakeEpisodeAssetLoader()
      .respond(to: episode.episode.mediaURL) { _ in
        entered(true)
        await gate.wait()
        if fails { throw URLError(.cannotLoadFromNetwork) }
        return (true, .seconds(30))
      }
    let launcher = Container.shared.appLauncher()
    let startup = Task { await launcher.prepareForPlayback() }
    defer { gate.signal() }
    try await Wait.until({ entered() }, { "Saved media was not requested" })

    let coordinator = Container.shared.carPlayCoordinator()
    let oldController = FakeCarPlayInterfaceController()
    coordinator.connect(oldController)
    #expect(oldController.roots.count == 1)
    coordinator.disconnect(oldController)
    startup.cancel()

    let newController = FakeCarPlayInterfaceController()
    coordinator.connect(newController)
    defer { coordinator.disconnect(newController) }
    #expect(newController.roots.count == 1)
    oldController.completions[0](false, URLError(.cancelled))
    #expect(oldController.roots.count == 1)
    #expect(newController.roots.count == 1)

    gate.signal()
    await startup.value
    await launcher.prepareForPlayback()
    #expect(
      await Container.shared.fakeEpisodeAssetLoader().responseCount(for: episode.episode.mediaURL)
        == 1
    )
    #expect(newController.roots.count == 1)
    if !fails {
      #expect(Container.shared.sharedState().onDeck?.id == episode.id)
    }
  }

  @Test("simultaneous browsing and playback readiness starts shared observers once")
  func simultaneousReadiness() async throws {
    let launcher = Container.shared.appLauncher()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<10 {
        group.addTask { launcher.prepareForBrowsing() }
        group.addTask { await launcher.prepareForPlayback() }
        group.addTask { await launcher.prepareForForeground() }
      }
    }
    let observatory = Container.shared.observatory() as! FakeObservatory
    try await Wait.until(
      { observatory.allCallsInOrder.contains { $0.methodName == "smartLists" } },
      { "Smart Lists observer did not start" }
    )
    _ = try observatory.expectCalls(methodName: "smartLists")
    _ = try observatory.expectCalls(methodName: "tags")
    #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
  }

  @Test(
    "connect and disconnect preserve current paused or playing audio",
    arguments: [false, true]
  )
  func preservesPlayback(playing: Bool) async throws {
    let episode = try await Create.podcastEpisode(Create.unsavedEpisode(currentTime: .seconds(12)))
    let launcher = Container.shared.appLauncher()
    await launcher.prepareForPlayback()
    let player = Container.shared.playManager()
    try await player.load(episode)
    if playing { await player.play() }
    try await PlayHelpers.waitForAudioActive(true)
    let avPlayer = Container.shared.avPlayer() as! FakeAVPlayer
    let current = avPlayer.current
    let status = avPlayer.timeControlStatus
    let audioCalls = await Container.shared.fakeAudioSession().activeCalls
    let coordinator = Container.shared.carPlayCoordinator()

    for _ in 0..<5 {
      let controller = FakeCarPlayInterfaceController()
      coordinator.connect(controller)
      coordinator.connect(controller)
      #expect(controller.roots.count == 1)
      coordinator.disconnect(controller)
      controller.completions[0](false, nil)
      #expect(controller.roots.count == 1)
    }

    #expect(avPlayer.current === current)
    #expect(avPlayer.timeControlStatus == status)
    #expect(Container.shared.sharedState().onDeck?.id == episode.id)
    #expect(await Container.shared.fakeAudioSession().activeCalls == audioCalls)
  }

  @Test("late completion and old disconnect cannot mutate a replacement connection")
  func staleConnection() {
    let coordinator = Container.shared.carPlayCoordinator()
    let oldController = FakeCarPlayInterfaceController()
    let newController = FakeCarPlayInterfaceController()
    coordinator.connect(oldController)
    coordinator.connect(newController)
    coordinator.disconnect(oldController)
    oldController.completions[0](false, nil)
    newController.completions[0](true, nil)
    #expect(oldController.roots.count == 1)
    #expect(newController.roots.count == 1)
    coordinator.disconnect(newController)
  }

  @Test("reusing a controller still invalidates the old connection")
  func reusedController() {
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    coordinator.disconnect(controller)
    coordinator.connect(controller)
    controller.completions[0](false, nil)
    #expect(controller.roots.count == 2)
    controller.completions[1](true, nil)
    coordinator.disconnect(controller)
  }

  @Test("disconnect releases the controller even while completion is pending")
  func releasesController() {
    let coordinator = Container.shared.carPlayCoordinator()
    var controller: FakeCarPlayInterfaceController? = FakeCarPlayInterfaceController()
    weak let weakController = controller
    coordinator.connect(controller!)
    let completion = controller!.completions[0]
    coordinator.disconnect(controller!)
    controller = nil
    #expect(weakController == nil)
    completion(false, nil)
  }

  @Test("root failure provides native retry and disconnect clears its handlers")
  func recoverableRootFailure() throws {
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](false, URLError(.cannotConnectToHost))
    #expect(controller.roots.count == 2)
    let errorRoot = try #require(controller.roots.last as? CPTabBarTemplate)
    let list = try #require(errorRoot.templates.first as? CPListTemplate)
    let retry = try #require(list.sections.first?.items.first as? CPListItem)
    #expect(retry.text == "Retry")
    #expect(retry.detailText == "Couldn't load CarPlay.")
    let handler = try #require(retry.handler)
    controller.completions[1](true, nil)
    var completions = 0
    handler(retry) { completions += 1 }
    #expect(completions == 1)
    #expect(controller.roots.count == 3)
    #expect(retry.handler == nil)
    controller.completions[2](false, nil)
    let disconnectedRoot = try #require(controller.roots.last as? CPTabBarTemplate)
    let disconnectedList = try #require(disconnectedRoot.templates.first as? CPListTemplate)
    let disconnectedRetry = try #require(
      disconnectedList.sections.first?.items.first as? CPListItem
    )
    coordinator.disconnect(controller)
    #expect(disconnectedRetry.handler == nil)
    handler(retry) { completions += 1 }
    #expect(completions == 2)
    #expect(controller.roots.count == 4)
  }

  @Test("rejected recovery does not loop and reconnect can retry")
  func rejectedRecovery() {
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    coordinator.connect(controller)
    controller.completions[0](false, nil)
    controller.completions[1](false, nil)
    #expect(controller.roots.count == 2)
    coordinator.disconnect(controller)
    coordinator.connect(controller)
    #expect(controller.roots.count == 3)
    coordinator.disconnect(controller)
  }

  @Test("phone lifecycle reads its own scene environment while CarPlay connects")
  func phoneScenePhase() async throws {
    let sharedState = Container.shared.sharedState()
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    let host = TestHostingController(
      rootView: PhoneSceneView(appDelegate: AppDelegate()).environment(\.scenePhase, .inactive)
    )
    try await withHostedTestWindow(host) { _ in
      try await Wait.until(
        { sharedState.scenePhase == .inactive },
        { "Phone scene did not publish its own inactive phase" }
      )
      coordinator.connect(controller)
      #expect(sharedState.scenePhase == .inactive)
      for phase in [ScenePhase.active, .background, .inactive] {
        host.rootView = PhoneSceneView(appDelegate: AppDelegate()).environment(\.scenePhase, phase)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Wait.until(
          { sharedState.scenePhase == phase },
          {
            "Phone phase is \(sharedState.scenePhase), expected \(phase) while CarPlay is connected"
          }
        )
        #expect(controller.roots.count == 1)
        #expect(controller.pushed.isEmpty)
        #expect(sharedState.onDeck == nil)
      }
      coordinator.disconnect(controller)
      #expect(sharedState.scenePhase == .inactive)
      #expect(await Container.shared.fakeAudioSession().activeCalls.isEmpty)
    }
  }
}
