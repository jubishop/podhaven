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
  private let refreshTask = ThreadSafe<Task<Void, Never>?>(nil)
  private let bgTask = ThreadSafe<Task<Bool, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    schedule(in: backgroundPolicy.cadence)
  }

  // MARK: - Background Task Scheduling

  func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
      using: nil
    ) { [weak self] task in
      guard let self else { return }

      let taskWrapper = UncheckedSendable(task)
      let didComplete = ThreadSafe(false)
      let complete: @Sendable (Bool) -> Void = { [didComplete, taskWrapper] success in
        guard !didComplete() else { return }
        didComplete(true)
        taskWrapper.value.setTaskCompleted(success: success)
      }

      task.expirationHandler = { [weak self, complete] in
        guard let self else { return }

        Self.log.debug("handle: expiration triggered, cancelling running task")

        bgTask()?.cancel()
        bgTask(nil)
        complete(false)
      }

      schedule(in: backgroundPolicy.cadence)

      Task { [weak self, complete] in
        guard let self
        else {
          complete(false)
          return
        }

        let success = await executeBGTask()
        complete(success)

        if await UIApplication.shared.applicationState == .active {
          Self.log.debug("App foregrounded during BGTask: beginning foreground refreshing")

          beginForegroundRefreshing()
        }
      }
    }
  }

  func schedule(in duration: Duration) {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
      Self.log.debug("scheduled next background refresh in: \(duration)")
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Background Task

  private func executeBGTask() async -> Bool {
    Self.log.debug("bgTask: performing refresh")

    let task: Task<Bool, Never> = Task(priority: .background) { [weak self] in
      guard let self else { return false }

      do {
        try await executeRefresh(backgroundPolicy)
        return true
      } catch {
        Self.log.error(error)
        return false
      }
    }

    bgTask(task)
    let success = await task.value
    bgTask(nil)

    Self.log.debug("bgTask: refresh completed gracefully")

    return success
  }

  // MARK: - Foreground Task

  private func beginForegroundRefreshing() {
    Self.log.debug("starting foreground refresh task loop")

    if refreshLock.claimed {
      Self.log.debug("foreground refresh: already refreshing")
      return
    }

    refreshTask()?.cancel()
    refreshTask(
      Task(priority: .background) { [weak self] in
        guard let self else { return }

        try? await sleeper.sleep(for: initialDelay)

        Self.log.debug("refreshTask: done initial sleeping")

        while await UIApplication.shared.applicationState == .active {
          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshScheduler.refreshTask"
          )
          do {
            Self.log.debug("refreshTask: performing refresh")

            try await executeRefresh(foregroundPolicy)

            Self.log.debug("refreshTask: refresh completed gracefully")
          } catch {
            Self.log.error(error)
          }
          await backgroundTask.end()

          Self.log.debug("refreshTask: now sleeping")
          try? await sleeper.sleep(for: foregroundPolicy.cadence)
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

      schedule(in: backgroundPolicy.cadence)
    default:
      break
    }
  }
}
