// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import Sentry
import SwiftUI

protocol AppHangTracking: Sendable {
  func pause()
  func resume()
}

struct SentryAppHangTracking: AppHangTracking {
  fileprivate init() {}

  func pause() { SentrySDK.pauseAppHangTracking() }
  func resume() { SentrySDK.resumeAppHangTracking() }
}

extension Container {
  var appHangTracking: Factory<any AppHangTracking> {
    Factory(self) { SentryAppHangTracking() }.scope(.cached)
  }

  var appHangReportingGate: Factory<AppHangReportingGate> {
    Factory(self) { AppHangReportingGate() }.scope(.cached)
  }
}

// Sentry counts a foreground CarPlay scene as app foreground while the phone
// renders no frames, so reporting follows the phone scene's reported phase,
// never the shared phase's default.
struct AppHangReportingGate: Sendable {
  @DynamicInjected(\.appHangTracking) private var tracking

  private static let log = Log.as("AppHangReportingGate")

  fileprivate init() {}

  func start() {
    tracking.pause()
    Self.log.debug("Paused app-hang reporting until the phone scene is active")
  }

  func handleScenePhaseChange(to phase: ScenePhase) {
    guard phase == .active else {
      tracking.pause()
      Self.log.debug("Paused app-hang reporting: phone scene is \(phase)")
      return
    }

    tracking.resume()
    Self.log.debug("Resumed app-hang reporting: phone scene is active")
  }
}
