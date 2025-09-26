// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import FactoryKit
import Foundation
import Logging
import UIKit

extension Container {
  var refreshScheduler: Factory<RefreshScheduler> {
    Factory(self) { RefreshScheduler() }.scope(.cached)
  }
}

final class RefreshScheduler: Sendable {
  private var connectionState: ConnectionState { Container.shared.connectionState() }
  private var notifications: (Notification.Name) -> any AsyncSequence<Notification, Never> {
    Container.shared.notifications()
  }
  private var refreshManager: RefreshManager { Container.shared.refreshManager() }
  private var sleeper: any Sleepable { Container.shared.sleeper() }

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.refresh"

  private let initialDelay = Duration.seconds(5)

  typealias RefreshPolicy = (cadence: Duration, cellLimit: Int, wifiLimit: Int)
  private let backgroundPolicy: RefreshPolicy = (cadence: .minutes(15), cellLimit: 4, wifiLimit: 16)
  private let foregroundPolicy: RefreshPolicy = (cadence: .minutes(5), cellLimit: 8, wifiLimit: 32)

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  // MARK: - State Management

  private let currentlyRefreshing = ThreadSafe(false)
  private let refreshTask = ThreadSafe<Task<Void, Never>?>(nil)
  private let bgTask = ThreadSafe<Task<Bool, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    Assert.neverCalled()

    Self.log.debug("start: executing")

    schedule(in: backgroundPolicy.cadence)
    startListeningToActivation()
    startListeningToBackgrounding()
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

        let success = await handle()
        complete(success)

        if await UIApplication.shared.applicationState == .active {
          activated()
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

  private func backgrounded() {
    Self.log.debug("backgrounded: scheduling BGAppRefreshTask")

    schedule(in: backgroundPolicy.cadence)
  }

  // MARK: - Background Task

  private func handle() async -> Bool {
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

  private func activated() {
    Self.log.debug("activated: starting foreground refresh task loop")

    if currentlyRefreshing() {
      Self.log.debug("activated: already refreshing")
      return
    }

    refreshTask()?.cancel()
    refreshTask(
      Task(priority: .background) { [weak self] in
        guard let self else { return }

        try? await sleeper.sleep(for: initialDelay)

        Self.log.debug("refreshTask: done initial sleeping")

        while await UIApplication.shared.applicationState == .active && !Task.isCancelled {
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

  func claimRefreshing() -> Bool {
    currentlyRefreshing {
      if $0 { return false }
      $0 = true
      return true
    }
  }

  func executeRefresh(_ refreshPolicy: RefreshPolicy) async throws {
    if connectionState.isConstrained {
      Self.log.debug("connection is constrained (low data mode)")
      return
    }

    if !claimRefreshing() {
      Self.log.debug("failed to claim refreshing: already refreshing")
      return
    }
    defer { currentlyRefreshing(false) }

    try await refreshManager.performRefresh(
      filter: Podcast.subscribed,
      limit: connectionState.isExpensive
        ? refreshPolicy.cellLimit
        : refreshPolicy.wifiLimit
    )
  }

  // MARK: - Notifications

  private func startListeningToActivation() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }

      if await UIApplication.shared.applicationState == .active {
        Self.log.debug("app already active")
        activated()
      } else {
        Self.log.debug("app not active, waiting for activation")
      }

      for await _ in notifications(UIApplication.didBecomeActiveNotification)
      where await UIApplication.shared.applicationState == .active {
        activated()
      }
    }
  }

  private func startListeningToBackgrounding() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }

      if await UIApplication.shared.applicationState == .background {
        Self.log.debug("app already backgrounded")
        backgrounded()
      } else {
        Self.log.debug("app is active, waiting for backgrounding")
      }

      for await _ in notifications(UIApplication.didEnterBackgroundNotification) {
        backgrounded()
      }
    }
  }
}
