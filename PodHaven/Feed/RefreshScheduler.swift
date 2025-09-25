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

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  // MARK: - State Management

  private let currentlyRefreshing = ThreadSafe(false)
  private let refreshTask = ThreadSafe<Task<Void, Never>?>(nil)
  private let bgTask = ThreadSafe<Task<Bool, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    Self.log.debug("start: executing")

    schedule(in: 15.minutes)
    startListeningToActivation()
  }

  // MARK: - Background Task Scheduling

  func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
      using: nil
    ) { task in
      task.expirationHandler = { [weak self] in
        guard let self else { return }

        Self.log.debug("handle: expiration triggered, cancelling running task")
        bgTask()?.cancel()
        task.setTaskCompleted(success: false)
      }

      self.schedule(in: 15.minutes)

      Task { [weak self, taskWrapper = UncheckedSendable(task)] in
        guard let self else { return }

        let success = await self.handle()
        taskWrapper.value.setTaskCompleted(success: success)
      }
    }
  }

  func schedule(in timeInterval: TimeInterval) {
    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: timeInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
      Self.log.debug("scheduled next background refresh in: \(timeInterval)")
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Background Task Handling

  private func handle() async -> Bool {
    Self.log.debug("handling background refresh callback")

    let currentPath = connectionState.currentPath

    if currentPath.status != .satisfied {
      Self.log.debug("connection is unsatisfied")
      return true
    }

    if currentPath.isConstrained || currentPath.isUltraConstrained {
      Self.log.debug("connection is constrained (low data mode)")
      return true
    }

    let task: Task<Bool, Never> = Task(priority: .background) { [weak self] in
      guard let self else { return false }

      do {
        try await self.refreshManager.performRefresh(
          filter: Podcast.subscribed,
          limit: currentPath.isExpensive ? 4 : 16
        )
        Self.log.debug("handle: refresh completed")
        return true
      } catch {
        Self.log.error(error)
        return false
      }
    }

    bgTask(task)
    return (await task.value)
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
            try await refreshManager.performRefresh(
              filter: Podcast.subscribed,
              limit: 64
            )
            Self.log.debug("refreshTask: refresh completed gracefully")
          } catch {
            Self.log.error(error)
          }
          currentlyRefreshing(false)
          Task { await backgroundTask.end() }

          Self.log.debug("refreshTask: now sleeping")
          try? await self.sleeper.sleep(for: .minutes(15))
        }
      }
    )
  }

  private func startListeningToActivation() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }

      try? await sleeper.sleep(for: .seconds(15))

      if await UIApplication.shared.applicationState == .active {
        Self.log.debug("app already active, activating refresh task")
        activated()
      } else {
        Self.log.debug("app not active, waiting for activation")
      }

      for await _ in notifications(UIApplication.didBecomeActiveNotification) {
        activated()
      }
    }
  }
}
