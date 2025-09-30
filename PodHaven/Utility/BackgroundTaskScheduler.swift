// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import Foundation
import Logging

struct BackgroundTaskScheduler: Sendable {
  typealias Completion = @Sendable (Bool) -> Void

  private static let log = Log.as("BackgroundTaskScheduler")

  private let identifier: String
  private let cadence: Duration
  private let bgTask: ThreadSafe<Task<Bool, Never>?>

  init(
    identifier: String,
    cadence: Duration,
    bgTask: ThreadSafe<Task<Bool, Never>?>
  ) {
    self.identifier = identifier
    self.cadence = cadence
    self.bgTask = bgTask
  }

  func register(executionTask: @escaping @Sendable (Completion) async -> Void) {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier,
      using: nil
    ) { task in
      let taskWrapper = UncheckedSendable(task)
      let didComplete = ThreadSafe(false)
      let complete: Completion = { [didComplete, taskWrapper] success in
        guard !didComplete() else { return }
        didComplete(true)
        taskWrapper.value.setTaskCompleted(success: success)
      }

      task.expirationHandler = {
        Self.log.debug("handle: expiration triggered, cancelling running task for: \(identifier)")

        bgTask()?.cancel()
        bgTask(nil)
        complete(false)
      }

      scheduleNext()
      Task { await executionTask(complete) }
    }
  }

  func scheduleNext(in passedDuration: Duration? = nil) {
    let duration = passedDuration ?? cadence

    let request = BGAppRefreshTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)

    do {
      try BGTaskScheduler.shared.submit(request)
      Self.log.debug("scheduled next background task \(identifier) in: \(duration)")
    } catch {
      Self.log.error(error)
    }
  }
}
