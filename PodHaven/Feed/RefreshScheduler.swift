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

        if let backgroundTask = bgTask() {
          backgroundTask.cancel()
          bgTask(nil)
        }
        complete(false)
      }

      schedule(in: backgroundPolicy.cadence)

      Task { [weak self, complete] in
        guard let self
        else {
          complete(false)
          return
        }

        let success = await self.handle()
        complete(success)
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

  // MARK: - Background Task Handling

  private func handle() async -> Bool {
    Self.log.debug("bgTask handling background refresh callback")

    if connectionState.isConstrained {
      Self.log.debug("bgTask: connection is constrained (low data mode)")
      return true
    }

    let task: Task<Bool, Never> = Task(priority: .background) { [weak self] in
      guard let self else { return false }

      do {
        try await self.refreshManager.performRefresh(
          filter: Podcast.subscribed,
          limit: connectionState.isExpensive
            ? backgroundPolicy.cellLimit
            : backgroundPolicy.wifiLimit
        )
        Self.log.debug("bgTask handle: refresh completed")
        return true
      } catch {
        Self.log.error(error)
        return false
      }
    }

    bgTask(task)
    let success = await task.value
    bgTask(nil)
    return success
  }

  // MARK: - Foreground Loop Refreshing

  private func activated() {
    Self.log.debug("activated: starting refresh task")

    if currentlyRefreshing() {
      Self.log.debug("activated: already refreshing")
      return
    }

    refreshTask()?.cancel()
    refreshTask(
      Task(priority: .background) { [weak self] in
        guard let self else { return }

        while !Task.isCancelled {
          let backgroundTask = await BackgroundTask.start(
            withName: "RefreshManager.refreshTask"
          )
          currentlyRefreshing(true)
          do {
            Self.log.debug("refreshTask: performing refresh")

            let performRefreshTask: () async throws -> Void = { [weak self] in
              guard let self else { return }

              if connectionState.isConstrained {
                Self.log.debug("refreshTask: connection is constrained (low data mode)")
                return
              }

              try await refreshManager.performRefresh(
                filter: Podcast.subscribed,
                limit: connectionState.isExpensive
                  ? foregroundPolicy.cellLimit
                  : foregroundPolicy.wifiLimit
              )
            }
            try await performRefreshTask()

            Self.log.debug("refreshTask: refresh completed gracefully")
          } catch {
            Self.log.error(error)
          }
          currentlyRefreshing(false)
          await backgroundTask.end()

          Self.log.debug("refreshTask: now sleeping")
          try? await self.sleeper.sleep(for: foregroundPolicy.cadence)
        }
      }
    )
  }

  private func backgrounded() {
    Self.log.debug("backgrounded: scheduling BGAppRefreshTask")

    schedule(in: backgroundPolicy.cadence)
  }

  private func startListeningToActivation() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }

      try? await sleeper.sleep(for: .seconds(15))

      if await UIApplication.shared.applicationState == .active {
        Self.log.debug("app already active")
        activated()
      } else {
        Self.log.debug("app not active, waiting for activation")
      }

      for await _ in notifications(UIApplication.didBecomeActiveNotification) {
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
