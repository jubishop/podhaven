// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("of AppHangReportingGate tests", .container)
@MainActor struct AppHangReportingGateTests {
  @DynamicInjected(\.appHangReportingGate) private var gate
  @DynamicInjected(\.sharedState) private var sharedState

  private var tracking: FakeAppHangTracking {
    Container.shared.appHangTracking() as! FakeAppHangTracking
  }

  @Test("reporting starts paused and the default phone phase does not resume it")
  func startsPaused() {
    gate.start()

    #expect(sharedState.scenePhase == .active)
    #expect(tracking.state == .paused)
  }

  @Test("a CarPlay connection without a phone scene report keeps reporting paused")
  func carPlayOnlyLaunchStaysPaused() {
    gate.start()
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    defer { coordinator.disconnect(controller) }

    coordinator.connect(controller)

    #expect(controller.roots.count == 1)
    #expect(sharedState.scenePhase == .active)
    #expect(tracking.state == .paused)
  }

  @Test("the phone scene's own phase drives reporting while CarPlay stays connected")
  func phoneScenePhaseDrivesReporting() async throws {
    gate.start()
    let tracking = self.tracking
    let sharedState = self.sharedState
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
      defer { coordinator.disconnect(controller) }
      #expect(tracking.state == .paused)

      let transitions: [(ScenePhase, FakeAppHangTracking.State)] = [
        (.active, .reporting), (.background, .paused), (.active, .reporting),
        (.inactive, .paused), (.active, .reporting),
      ]
      for (phase, expected) in transitions {
        host.rootView = PhoneSceneView(appDelegate: AppDelegate()).environment(\.scenePhase, phase)
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        try await Wait.until(
          { sharedState.scenePhase == phase },
          { "Phone phase is \(sharedState.scenePhase), expected \(phase)" }
        )
        #expect(tracking.state == expected)
      }
    }
  }
}
