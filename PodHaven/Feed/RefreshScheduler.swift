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

  // desiredMode is the source of truth.
  // foregroundLoop reserves the single loop slot so duplicate start requests
  // cannot create orphaned foreground tasks.
  private enum DesiredMode: Sendable {
    case foreground
    case background
  }

  private struct ForegroundLoop: Sendable {
    let id: UUID
    var task: Task<Void, Never>?
  }

  private enum Event: Sendable {
    case sceneDidBecomeActive
    case sceneDidEnterBackground
    case foregroundLoopEnded(foregroundLoopID: UUID)
  }

  private enum Effect: Sendable {
    case startForegroundLoop(UUID)
    case cancelForegroundLoop(Task<Void, Never>)
    case scheduleBackgroundTask
  }

  private struct State: Sendable {
    var desiredMode: DesiredMode = .background
    var foregroundLoop: ForegroundLoop?
    var isRefreshInFlight = false

    mutating func transition(for event: Event) -> [Effect] {
      switch event {
      case .sceneDidBecomeActive:
        desiredMode = .foreground
        return reconcileForegroundLoop()
      case .sceneDidEnterBackground:
        desiredMode = .background

        var effects: [Effect] = []
        if let foregroundLoopToCancel = foregroundLoop?.task {
          effects.append(.cancelForegroundLoop(foregroundLoopToCancel))
        }
        foregroundLoop = nil
        effects.append(.scheduleBackgroundTask)

        return effects
      case .foregroundLoopEnded(let foregroundLoopID):
        guard foregroundLoop?.id == foregroundLoopID else { return [] }

        foregroundLoop = nil
        return []
      }
    }

    mutating func installForegroundLoop(
      _ task: Task<Void, Never>,
      foregroundLoopID: UUID
    ) -> Task<Void, Never>? {
      guard desiredMode == .foreground else { return task }
      guard foregroundLoop?.id == foregroundLoopID else { return task }

      foregroundLoop?.task = task
      return nil
    }

    func shouldContinueForegroundLoop(foregroundLoopID: UUID) -> Bool {
      desiredMode == .foreground
        && foregroundLoop?.id == foregroundLoopID
    }

    mutating func beginRefreshIfNeeded() -> Bool {
      guard !isRefreshInFlight else { return false }

      isRefreshInFlight = true
      return true
    }

    mutating func finishRefresh() -> [Effect] {
      guard isRefreshInFlight else { return [] }

      isRefreshInFlight = false
      return reconcileForegroundLoop()
    }

    private mutating func reconcileForegroundLoop() -> [Effect] {
      guard desiredMode == .foreground else { return [] }
      guard !isRefreshInFlight else { return [] }
      guard foregroundLoop == nil else { return [] }

      let foregroundLoopID = UUID()
      foregroundLoop = ForegroundLoop(id: foregroundLoopID)

      return [.startForegroundLoop(foregroundLoopID)]
    }
  }

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

        try await runRefresh(backgroundPolicy)
        try Task.checkCancellation()

        Self.log.debug("background refresh: completed gracefully")

        complete(true)
      } catch {
        Self.log.caughtError("register: background refresh failed", error)
        complete(false)
      }
    }
  }

  // MARK: - Foreground Task

  private func handle(_ event: Event) {
    let effects = state { $0.transition(for: event) }
    apply(effects)
  }

  private func apply(_ effects: [Effect]) {
    for effect in effects {
      switch effect {
      case .startForegroundLoop(let foregroundLoopID):
        startForegroundLoop(foregroundLoopID: foregroundLoopID)
      case .cancelForegroundLoop(let task):
        task.cancel()
      case .scheduleBackgroundTask:
        backgroundTaskScheduler.scheduleNext()
      }
    }
  }

  private func startForegroundLoop(foregroundLoopID: UUID) {
    Self.log.debug("starting foreground refresh task loop")

    let task = foregroundRefreshTask(foregroundLoopID: foregroundLoopID)
    let foregroundLoopToCancel = state {
      $0.installForegroundLoop(task, foregroundLoopID: foregroundLoopID)
    }
    foregroundLoopToCancel?.cancel()
  }

  private func foregroundRefreshTask(foregroundLoopID: UUID) -> Task<Void, Never> {
    Task(priority: .utility) {
      defer { handle(.foregroundLoopEnded(foregroundLoopID: foregroundLoopID)) }

      do {
        try await sleeper.sleep(for: .seconds(3))

        Self.log.debug("foregroundRefreshTask: done initial sleeping")

        while shouldContinueForegroundRefreshing(foregroundLoopID: foregroundLoopID) {
          try Task.checkCancellation()
          guard await application.applicationState == .active else { return }

          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshScheduler.foregroundRefreshTask"
          )
          var shouldExit = false
          do {
            Self.log.debug("foregroundRefreshTask: performing refresh")

            try await runRefresh(foregroundPolicy)
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

  private func shouldContinueForegroundRefreshing(foregroundLoopID: UUID) -> Bool {
    state { $0.shouldContinueForegroundLoop(foregroundLoopID: foregroundLoopID) }
  }

  // MARK: - Refresh Helpers

  private func runRefresh(_ refreshPolicy: RefreshPolicy) async throws {
    if connectionState.isConstrained {
      Self.log.debug("connection is constrained (low data mode)")
      return
    }

    let shouldRunRefresh = state { $0.beginRefreshIfNeeded() }
    if !shouldRunRefresh {
      Self.log.debug("failed to claim refreshing: already refreshing")
      return
    }
    defer { finishRefresh() }

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

  private func finishRefresh() {
    let effects = state { $0.finishRefresh() }
    apply(effects)
  }

  // MARK: - Phase Changes

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      Self.log.debug("activated")

      handle(.sceneDidBecomeActive)
    case .background:
      Self.log.debug("backgrounded")

      handle(.sceneDidEnterBackground)
    default:
      break
    }
  }
}
