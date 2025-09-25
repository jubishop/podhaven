// Copyright Justin Bishop, 2025

import BackgroundTasks
import FactoryKit
import Foundation
import Logging

extension Container {
  var refreshScheduler: Factory<RefreshScheduler> {
    Factory(self) { RefreshScheduler() }.scope(.cached)
  }
}

final class RefreshScheduler {
  @DynamicInjected(\.connectionState) private var connectionState
  @DynamicInjected(\.refreshManager) private var refreshManager

  private static let backgroundTaskIdentifier = "com.justinbishop.podhaven.refresh"

  private static let log = Log.as(LogSubsystem.Feed.refreshScheduler)

  private var runningTask: Task<Void, Never>?

  // MARK: - Schedule Management

  func register() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.backgroundTaskIdentifier,
      using: nil
    ) { task in
      task.expirationHandler = { [weak self] in
        guard let self else { return }

        Self.log.debug("handle: expiration triggered, cancelling running task")
        runningTask?.cancel()
        task.setTaskCompleted(success: false)
      }

      self.schedule(in: 15.minutes)
      task.setTaskCompleted(success: self.handle())
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

  // MARK: - Private

  private func handle() -> Bool {
    Self.log.debug("handling background refresh callback")

    if connectionState.currentPath.status != .satisfied {
      Self.log.debug("connectivity unavailable")
      return true
    }

    if connectionState.currentPath.isConstrained {
      Self.log.debug("connectivity constrained (low data mode)")
      return true
    }

    return true
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
