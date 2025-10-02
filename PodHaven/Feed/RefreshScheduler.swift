// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import FactoryKit
import Foundation
import Logging
import SwiftUI
import UIKit

extension Container {
  var refreshScheduler: Factory<RefreshScheduler> {
    Factory(self) { RefreshScheduler() }.scope(.cached)
  }
}

final class RefreshScheduler: Sendable {
  private var connectionState: ConnectionState { Container.shared.connectionState() }
  private var refreshManager: RefreshManager { Container.shared.refreshManager() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.refresh"

  private let initialDelay = Duration.seconds(5)

  typealias RefreshPolicy = (
    stalenessThreshold: Duration,
    cadence: Duration,
    cellLimit: Int,
    wifiLimit: Int
  )
  private let backgroundPolicy: RefreshPolicy = (
    stalenessThreshold: .hours(2),
    cadence: .minutes(15),
    cellLimit: 4,
    wifiLimit: 16
  )
  private let foregroundPolicy: RefreshPolicy = (
    stalenessThreshold: .hours(1),
    cadence: .minutes(5),
    cellLimit: 8,
    wifiLimit: 32
  )

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  // MARK: - State Management

  private let refreshLock = ThreadLock()
  private let foregroundRefreshTask = ThreadSafe<Task<Void, Error>?>(nil)
  private let backgroundTaskScheduler: BackgroundTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: backgroundPolicy.cadence
    )
  }

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    backgroundTaskScheduler.scheduleNext(in: backgroundPolicy.cadence)
  }

  // MARK: - Background Task

  func register() {
    backgroundTaskScheduler.register { [weak self] complete in
      guard let self
      else {
        complete(false)
        return
      }

      do {
        Self.log.debug("background refresh: performing refresh")

        try await executeRefresh(foregroundPolicy)
        try Task.checkCancellation()

        Self.log.debug("background refresh: completed gracefully")

        complete(true)
      } catch {
        Self.log.error(error)
        complete(false)
      }

      if await UIApplication.shared.applicationState == .active {
        Self.log.debug("App foregrounded during BGTask: beginning foreground refreshing")

        beginForegroundRefreshing()
      }
    }
  }

  // MARK: - Foreground Task

  private func beginForegroundRefreshing() {
    Self.log.debug("starting foreground refresh task loop")

    if refreshLock.isClaimed {
      Self.log.debug("foreground refresh: already refreshing")
      return
    }

    foregroundRefreshTask()?.cancel()
    foregroundRefreshTask(
      Task(priority: .background) { [weak self] in
        guard let self else { return }

        try await sleeper.sleep(for: initialDelay)

        Self.log.debug("foregroundRefreshTask: done initial sleeping")

        while await UIApplication.shared.applicationState == .active {
          try Task.checkCancellation()

          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshScheduler.foregroundRefreshTask"
          )
          do {
            Self.log.debug("foregroundRefreshTask: performing refresh")

            try await executeRefresh(foregroundPolicy)

            Self.log.debug("foregroundRefreshTask: refresh completed gracefully")
          } catch {
            Self.log.error(error)
          }
          await backgroundTask.end()

          Self.log.debug("foregroundRefreshTask: now sleeping")
          try await sleeper.sleep(for: foregroundPolicy.cadence)
        }
      }
    )
  }

  // MARK: - Refresh Helpers

  func executeRefresh(_ refreshPolicy: RefreshPolicy) async throws {
    if connectionState.isConstrained {
      Self.log.debug("connection is constrained (low data mode)")
      return
    }

    if !refreshLock.claim() {
      Self.log.debug("failed to claim refreshing: already refreshing")
      return
    }
    defer { refreshLock.release() }

    try await refreshManager.performRefresh(
      stalenessThreshold: refreshPolicy.stalenessThreshold,
      filter: Podcast.subscribed,
      limit: connectionState.isExpensive
        ? refreshPolicy.cellLimit
        : refreshPolicy.wifiLimit
    )
  }

  // MARK: - Phase Changes

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      Self.log.debug("activated")

      beginForegroundRefreshing()
    case .background:
      Self.log.debug("backgrounded")

      backgroundTaskScheduler.scheduleNext(in: backgroundPolicy.cadence)
    default:
      break
    }
  }
}
