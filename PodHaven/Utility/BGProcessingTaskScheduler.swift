// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import Foundation
import Logging

struct BGProcessingTaskScheduler: Sendable {
  typealias Completion = @Sendable (Bool) -> Void

  private static let log = Log.as("BGProcessingTaskScheduler")

  private let registered = ThreadLock()
  private let identifier: String
  private let cadence: Duration
  private let requiresNetworkConnectivity: Bool

  // MARK: - Helpers

  // For Debugging/Logging only.
  static func formatPendingTasks(_ requests: [BGTaskRequest]) -> String {
    requests.map { request in
      let date: String
      if let beginDate = request.earliestBeginDate {
        date = beginDate.formatted(date: .abbreviated, time: .shortened)
      } else {
        date = "none"
      }
      return "  - \(request.identifier) (earliest: \(date))"
    }
    .joined(separator: "\n  ")
  }

  init(
    identifier: String,
    cadence: Duration,
    requiresNetworkConnectivity: Bool = false
  ) {
    self.identifier = identifier
    self.cadence = cadence
    self.requiresNetworkConnectivity = requiresNetworkConnectivity

    Self.log.debug("BGProcessingTaskScheduler with identifier: \(identifier)")
  }

  func register(executionTask: @escaping @Sendable (Completion) async -> Void) {
    Self.log.info("register() called for: \(identifier)")

    guard registered.claim() else {
      Self.log.warning("Registration for BackgroundTask: \(identifier) has already been made?")
      return
    }

    let success = BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier,
      using: nil
    ) { task in
      Self.log.debug("iOS is executing the background task: \(identifier)")

      let taskWrapper = UncheckedSendable(task)
      let didComplete = ThreadLock()
      let complete: Completion = { [didComplete, taskWrapper] success in
        guard didComplete.claim() else { return }
        taskWrapper.value.setTaskCompleted(success: success)
      }

      var bgTask: Task<Void, Never>? = nil
      task.expirationHandler = { [complete] in
        Self.log.debug("handle: expiration triggered, cancelling running task for: \(identifier)")

        bgTask?.cancel()
        complete(false)
      }

      scheduleNext()
      bgTask = Task(priority: .background) { await executionTask(complete) }
    }

    Self.log.info(
      """
      BGTaskScheduler.shared.register returned: \(success)
      Registration for BackgroundTask: \(identifier) complete
      """
    )
  }

  func scheduleNext(in passedDuration: Duration? = nil) {
    let duration = passedDuration ?? cadence

    Self.log.debug("scheduleNext() called for: \(identifier)")

    let request = BGProcessingTaskRequest(identifier: identifier)
    request.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)
    request.requiresNetworkConnectivity = requiresNetworkConnectivity
    request.requiresExternalPower = false

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      Self.log.caughtError("scheduleNext: failed to submit background task '\(identifier)'", error)
      return
    }

    Self.log.debug(
      """
      scheduled next background task: \(identifier)
        duration: \(duration)
        earliest begin date: \(request.earliestBeginDate?.description ?? "nil")
      """
    )

    BGTaskScheduler.shared.getPendingTaskRequests { requests in
      Self.log.debug(
        """
        Pending background tasks:
          \(Self.formatPendingTasks(requests))
        """
      )
    }
  }
}
