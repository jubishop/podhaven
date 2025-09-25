// Copyright Justin Bishop, 2025

import BackgroundTasks
import FactoryKit
import Foundation
import Logging

extension Container {
  var refreshBackgroundScheduler: Factory<RefreshBackgroundScheduler> {
    Factory(self) { RefreshBackgroundScheduler() }.scope(.cached)
  }
}

final class RefreshBackgroundScheduler {
  @DynamicInjected(\.connectionState) private var connectionState
  @DynamicInjected(\.refreshManager) private var refreshManager

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.refresh"

  private static let log = Log.as(LogSubsystem.Feed.refreshManager)

  //  private var runningTask: Task<RefreshIterationResult, Never>?

  func register() {
    //    BGTaskScheduler.shared.register(
    //      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
    //      using: nil
    //    ) { task in
    //      guard let appRefreshTask = task as? BGAppRefreshTask else {
    //        task.setTaskCompleted(success: false)
    //        return
    //      }
    //
    //      Task { [weak self] in
    //        guard let self else { return }
    //        await self.handle(task: appRefreshTask)
    //      }
    //    }
  }

  func schedule() {
    //    let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
    //    request.earliestBeginDate = earliestBeginDate(for: reason)
    //
    //    do {
    //      try BGTaskScheduler.shared.submit(request)
    //      Self.log.debug(
    //        "schedule: scheduled next background refresh for reason: \(reason.logDescription)"
    //      )
    //    } catch {
    //      Self.log.error(
    //        "schedule: failed to submit BGAppRefreshTaskRequest: \(error.localizedDescription)"
    //      )
    //    }
    //  }
    //
    //  // MARK: - Private
    //
    //  private func handle(task: BGAppRefreshTask) async {
    //    Self.log.debug("handle: received BGAppRefreshTask")
    //
    //    let policy = RefreshPolicy.policy(for: connectivityMonitor.currentStatus)
    //
    //    guard policy.status.allowsRefresh else {
    //      Self.log.debug("handle: connectivity unavailable, completing without refresh")
    //      schedule(reason: .afterCompletion(result: .init(succeeded: true, policy: policy)))
    //      task.setTaskCompleted(success: true)
    //      return
    //    }
    //
    //    schedule(reason: .initial)
    //
    //    task.expirationHandler = { [weak self] in
    //      Self.log.debug("handle: expiration triggered, cancelling running task")
    //      Task { @MainActor [weak self] in
    //        self?.runningTask?.cancel()
    //      }
    //    }
    //
    //    runningTask = Task(priority: .background) { [weak self] in
    //      guard let self else {
    //        return RefreshIterationResult(succeeded: false, policy: policy)
    //      }
    //
    //      do {
    //        let limit = policy.limit ?? Int.max
    //        try await self.refreshManager.performRefresh(
    //          stalenessThreshold: policy.stalenessThreshold,
    //          filter: Podcast.subscribed,
    //          limit: limit
    //        )
    //        Self.log.debug("handle: refresh completed")
    //        return RefreshIterationResult(succeeded: true, policy: policy)
    //      } catch {
    //        Self.log.error(error)
    //        return RefreshIterationResult(succeeded: false, policy: policy)
    //      }
    //    }
    //
    //    let result = await runningTask?.value ?? .init(succeeded: false, policy: policy)
    //    runningTask = nil
    //    task.setTaskCompleted(success: result.succeeded)
    //    schedule(reason: .afterCompletion(result: result))
    //  }
    //
    //  private func earliestBeginDate(for reason: ScheduleReason) -> Date? {
    //    let interval: TimeInterval
    //    switch reason {
    //    case .initial:
    //      interval = 30.minutes
    //    case .appDidEnterBackground:
    //      interval = 15.minutes
    //    case .afterCompletion(let iteration):
    //      interval = iteration.succeeded ? 30.minutes : 5.minutes
    //    }
    //
    //    return Date(timeIntervalSinceNow: interval)
  }
}
