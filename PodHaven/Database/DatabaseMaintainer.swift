// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI

extension Container {
  var databaseMaintainer: Factory<DatabaseMaintainer> {
    Factory(self) { DatabaseMaintainer() }.scope(.cached)
  }
}

// A DatabasePool keeps its connections open for the whole process, so SQLite's
// "run PRAGMA optimize before closing each connection" guidance never fires on
// its own. Backgrounding is the mobile analog of that close, and it recurs far
// more often than a cold launch, so refresh planner stats there.
struct DatabaseMaintainer: Sendable {
  private var appDB: AppDB { Container.shared.appDB() }

  private static let log = Log.as(LogSubsystem.Database.appDB)

  fileprivate init() {}

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    guard scenePhase == .background else { return }
    Task { @MainActor in
      let backgroundTask = BackgroundTask.start(withName: "databaseOptimize")
      defer { backgroundTask.end() }
      do {
        try await appDB.optimize()
      } catch {
        Self.log.caughtError("handleScenePhaseChange: PRAGMA optimize failed", error)
      }
    }
  }
}
