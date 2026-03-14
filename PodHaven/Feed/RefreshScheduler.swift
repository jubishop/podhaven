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

struct RefreshScheduler: Sendable {
  private var application: any ApplicationProviding { Container.shared.uiApplication() }
  private var connectionState: ConnectionState { Container.shared.connectionState() }
  private var refreshManager: RefreshManager { Container.shared.refreshManager() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).refresh"

  typealias RefreshPolicy = (
    cadence: Duration,
    cellStalenessThreshold: Duration,
    cellLimit: Int,
    wifiStalenessThreshold: Duration,
    wifiLimit: Int
  )
  private let backgroundPolicy: RefreshPolicy = (
    cadence: .hours(1),
    cellStalenessThreshold: .hours(8),
    cellLimit: 16,
    wifiStalenessThreshold: .hours(2),
    wifiLimit: 64
  )
  private let foregroundPolicy: RefreshPolicy = (
    cadence: .minutes(5),
    cellStalenessThreshold: .hours(4),
    cellLimit: 8,
    wifiStalenessThreshold: .hours(1),
    wifiLimit: 32
  )

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  // MARK: - State Management

  private let refreshLock = ThreadLock()
  private let foregroundRefreshTask = ThreadSafe<Task<Void, any Error>?>(nil)
  private let processingTaskScheduler: BGProcessingTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.processingTaskScheduler = BGProcessingTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: backgroundPolicy.cadence,
      requiresNetworkConnectivity: true
    )
  }

  func start() {
    guard Function.neverCalled() else { return }
    Self.log.debug("start: executing")

    processingTaskScheduler.scheduleNext(in: backgroundPolicy.cadence)
  }

  // MARK: - Background Task

  func register() {
    Self.log.debug("registering")

    processingTaskScheduler.register { complete in
      do {
        Self.log.debug("background refresh: performing refresh")

        try await executeRefresh(backgroundPolicy)
        try Task.checkCancellation()

        Self.log.debug("background refresh: completed gracefully")

        complete(true)
      } catch {
        Self.log.caughtError("register: background refresh failed", error)
        complete(false)
      }

      if await application.applicationState == .active {
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
      Task(priority: .background) {
        try await sleeper.sleep(for: .seconds(3))

        Self.log.debug("foregroundRefreshTask: done initial sleeping")

        while await application.applicationState == .active {
          try Task.checkCancellation()

          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshScheduler.foregroundRefreshTask"
          )
          do {
            Self.log.debug("foregroundRefreshTask: performing refresh")

            try await executeRefresh(foregroundPolicy)
            try Task.checkCancellation()

            Self.log.debug("foregroundRefreshTask: refresh completed gracefully")
          } catch {
            Self.log.caughtError("foregroundRefreshTask: refresh failed", error)
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
      stalenessThreshold: connectionState.isExpensive
        ? refreshPolicy.cellStalenessThreshold
        : refreshPolicy.wifiStalenessThreshold,
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

      processingTaskScheduler.scheduleNext(in: backgroundPolicy.cadence)
    default:
      break
    }
  }
}
