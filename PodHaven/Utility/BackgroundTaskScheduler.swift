// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import Foundation
import Logging

struct BackgroundTaskScheduler: Sendable {
  typealias Completion = @Sendable (Bool) -> Void

  enum TaskType {
    case appRefresh
    case processing
  }

  private static let log = Log.as("BackgroundTaskScheduler")

  private let registered = ThreadLock()
  private let identifier: String
  private let cadence: Duration
  private let taskType: TaskType

  // MARK: - Helpers

  // For Debugging/Logging only.
  static func formatPendingTasks(_ requests: [BGTaskRequest]) -> String {
    requests.map { request in
      let type = request is BGAppRefreshTaskRequest ? "appRefresh" : "processing"
      let date: String
      if let beginDate = request.earliestBeginDate {
        date = beginDate.formatted(date: .abbreviated, time: .shortened)
      } else {
        date = "none"
      }
      return "  - \(request.identifier) (\(type), earliest: \(date))"
    }
    .joined(separator: "\n  ")
  }

  init(identifier: String, cadence: Duration, taskType: TaskType) {
    self.identifier = identifier
    self.cadence = cadence
    self.taskType = taskType

    Self.log.debug("BackgroundTaskScheduler with identifier: \(identifier), type: \(taskType)")
  }

  func register(executionTask: @escaping @Sendable (Completion) async -> Void) {
    Self.log.notice("register() called for: \(identifier)")

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

    Self.log.notice(
      """
      BGTaskScheduler.shared.register returned: \(success)
      Registration for BackgroundTask: \(identifier) complete
      """
    )
  }

  func scheduleNext(in passedDuration: Duration? = nil) {
    let duration = passedDuration ?? cadence

    Self.log.debug("scheduleNext() called for: \(identifier), type: \(taskType)")

    let request: BGTaskRequest
    switch taskType {
    case .appRefresh:
      let refreshRequest = BGAppRefreshTaskRequest(identifier: identifier)
      refreshRequest.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)
      request = refreshRequest
    case .processing:
      let processingRequest = BGProcessingTaskRequest(identifier: identifier)
      processingRequest.earliestBeginDate = Date.now.advanced(by: duration.asTimeInterval)
      processingRequest.requiresNetworkConnectivity = false
      processingRequest.requiresExternalPower = false
      request = processingRequest
    }

    do {
      try BGTaskScheduler.shared.submit(request)
      Self.log.debug(
        """
        scheduled next background task: \(identifier)
          type: \(taskType)
          duration: \(duration)
          earliest begin date: \(request.earliestBeginDate!)
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
    } catch {
      Self.log.error(error)
    }
  }
}
