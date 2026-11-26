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
  @DynamicInjected(\.dateProvider) private var dateProvider
  @DynamicInjected(\.repo) private var repo

  private var appDB: AppDB { Container.shared.appDB() }

  static let publisherTranscriptByteBudget = 500_000_000
  private static let publisherTranscriptBudgetCheckInterval: TimeInterval = 24 * 60 * 60

  private static let log = Log.as(LogSubsystem.Database.appDB)

  @PersistedThreadSafe("publisherTranscriptBudgetCheckedAt")
  private var publisherTranscriptBudgetCheckedAt: Date? = nil

  fileprivate init() {}

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    guard scenePhase == .background else { return }
    Task { @MainActor in
      let backgroundTask = BackgroundTask.start(withName: "databaseMaintenance")
      defer { backgroundTask.end() }
      do {
        try await appDB.optimize()
      } catch {
        Self.log.caughtError("handleScenePhaseChange: PRAGMA optimize failed", error)
      }
      await checkPublisherTranscriptBudget()
    }
  }

  private func checkPublisherTranscriptBudget() async {
    let now = dateProvider.now
    let isDue = $publisherTranscriptBudgetCheckedAt.update { checkedAt in
      if let lastCheck = checkedAt,
        abs(now.timeIntervalSince(lastCheck)) < Self.publisherTranscriptBudgetCheckInterval
      {
        return false
      }
      checkedAt = now
      return true
    }
    guard isDue else { return }

    let byteCount: Int
    do {
      byteCount = try await repo.publisherTranscriptByteCount()
    } catch {
      Self.log.caughtError("checkPublisherTranscriptBudget: measurement failed", error)
      return
    }

    guard byteCount > Self.publisherTranscriptByteBudget else {
      Self.log.debug(
        """
        checkPublisherTranscriptBudget: publisher transcripts use \(byteCount) of \
        \(Self.publisherTranscriptByteBudget) budgeted bytes
        """
      )
      return
    }
    Self.log.warning(
      """
      checkPublisherTranscriptBudget: publisher transcripts use \(byteCount) bytes, over the \
      \(Self.publisherTranscriptByteBudget)-byte transcript storage budget; revisit their retention
      """
    )
  }
}
