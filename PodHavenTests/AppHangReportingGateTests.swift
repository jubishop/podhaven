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

  @Test("reporting resumes when the phone scene becomes active")
  func resumesWhenPhoneSceneActive() {
    gate.start()
    #expect(tracking.state == .paused)

    gate.handleScenePhaseChange(to: .active)

    #expect(tracking.state == .reporting)
  }

  @Test(
    "reporting pauses while the phone scene is not active and CarPlay stays connected",
    arguments: [ScenePhase.inactive, .background]
  )
  func pausesWhilePhoneSceneNotActive(phase: ScenePhase) {
    gate.start()
    let coordinator = Container.shared.carPlayCoordinator()
    let controller = FakeCarPlayInterfaceController()
    defer { coordinator.disconnect(controller) }
    coordinator.connect(controller)
    gate.handleScenePhaseChange(to: .active)
    #expect(tracking.state == .reporting)

    gate.handleScenePhaseChange(to: phase)

    #expect(tracking.state == .paused)

    gate.handleScenePhaseChange(to: .active)

    #expect(tracking.state == .reporting)
  }
}
