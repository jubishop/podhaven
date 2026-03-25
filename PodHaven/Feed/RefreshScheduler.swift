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

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).feedRefresh"

  typealias RefreshPolicy = (
    cadence: Duration,
    cellStalenessThreshold: Duration,
    cellLimit: Int,
    wifiStalenessThreshold: Duration,
    wifiLimit: Int
  )
  private let backgroundPolicy: RefreshPolicy = (
    cadence: .minutes(30),
    cellStalenessThreshold: .hours(4),
    cellLimit: 8,
    wifiStalenessThreshold: .hours(2),
    wifiLimit: 64
  )
  private let foregroundPolicy: RefreshPolicy = (
    cadence: .minutes(4),
    cellStalenessThreshold: .hours(2),
    cellLimit: 8,
    wifiStalenessThreshold: .hours(1),
    wifiLimit: 64
  )

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  // MARK: - State Management

  private enum DesiredMode: Sendable {
    case foreground
    case background
  }

  private struct State: Sendable {
    var desiredMode: DesiredMode = .background
    var foregroundLoopToken: UUID?
    var foregroundLoopTask: Task<Void, Never>?
  }

  private let refreshLock = ThreadLock()
  private let state = ThreadSafe(State())
  private let backgroundTaskScheduler: BackgroundTaskScheduler

  // MARK: - Initialization

  fileprivate init() {
    self.backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: backgroundPolicy.cadence,
      taskType: .appRefresh
    )
  }

  // MARK: - Background Task

  func register() {
    Self.log.debug("registering")

    backgroundTaskScheduler.register { complete in
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

        requestForegroundRefreshing()
      }
    }
  }

  // MARK: - Foreground Task

  private func requestForegroundRefreshing() {
    state { $0.desiredMode = .foreground }

    if refreshLock.isClaimed {
      Self.log.debug("foreground refresh: refresh already in flight, deferring loop start")
      return
    }

    startForegroundRefreshingIfNeeded()
  }

  private func startForegroundRefreshingIfNeeded() {
    let token = UUID()
    let shouldStart = state { value in
      guard value.foregroundLoopToken == nil else { return false }

      value.foregroundLoopToken = token
      return true
    }
    guard shouldStart else {
      Self.log.debug("foreground refresh task loop already active")
      return
    }

    Self.log.debug("starting foreground refresh task loop")

    let task = foregroundRefreshTask(token: token)
    let shouldCancel = state { value in
      guard value.foregroundLoopToken == token else { return true }
      guard value.desiredMode == .foreground else {
        value.foregroundLoopToken = nil
        value.foregroundLoopTask = nil
        return true
      }

      value.foregroundLoopTask = task
      return false
    }
    if shouldCancel {
      task.cancel()
    }
  }

  private func stopForegroundRefreshing() {
    let task = state { value -> Task<Void, Never>? in
      value.desiredMode = .background
      defer {
        value.foregroundLoopToken = nil
        value.foregroundLoopTask = nil
      }
      return value.foregroundLoopTask
    }
    task?.cancel()
  }

  private func foregroundRefreshTask(token: UUID) -> Task<Void, Never> {
    Task(priority: .background) {
      defer { clearForegroundLoopIfCurrent(token: token) }

      do {
        try await sleeper.sleep(for: .seconds(3))

        Self.log.debug("foregroundRefreshTask: done initial sleeping")

        while shouldContinueForegroundRefreshing(token: token) {
          try Task.checkCancellation()
          guard await application.applicationState == .active else { return }

          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshScheduler.foregroundRefreshTask"
          )
          var shouldExit = false
          do {
            Self.log.debug("foregroundRefreshTask: performing refresh")

            try await executeRefresh(foregroundPolicy)
            try Task.checkCancellation()

            Self.log.debug("foregroundRefreshTask: refresh completed gracefully")
          } catch is CancellationError {
            shouldExit = true
          } catch {
            Self.log.caughtError("foregroundRefreshTask: refresh failed", error)
          }
          await backgroundTask.end()
          if shouldExit { return }

          Self.log.debug("foregroundRefreshTask: now sleeping")
          try await sleeper.sleep(for: foregroundPolicy.cadence)
        }
      } catch {
        Self.log.caughtError("foregroundRefreshTask failed", error)
      }
    }
  }

  private func shouldContinueForegroundRefreshing(token: UUID) -> Bool {
    state { value in
      value.desiredMode == .foreground
        && value.foregroundLoopToken == token
    }
  }

  private func clearForegroundLoopIfCurrent(token: UUID) {
    state { value in
      guard value.foregroundLoopToken == token else { return }

      value.foregroundLoopToken = nil
      value.foregroundLoopTask = nil
    }
  }

  // MARK: - Refresh Helpers

  private func executeRefresh(_ refreshPolicy: RefreshPolicy) async throws {
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

      requestForegroundRefreshing()
    case .background:
      Self.log.debug("backgrounded")

      stopForegroundRefreshing()
      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }
}
