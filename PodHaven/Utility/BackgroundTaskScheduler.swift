// Copyright Justin Bishop, 2025

import BackgroundTasks
import ConcurrencyExtras
import Foundation
import Logging

enum BackgroundTaskType: Sendable {
  case processing(requiresNetworkConnectivity: Bool)
  case appRefresh

  func makeRequest(identifier: String) -> BGTaskRequest {
    switch self {
    case .processing(let requiresNetworkConnectivity):
      let request = BGProcessingTaskRequest(identifier: identifier)
      request.requiresNetworkConnectivity = requiresNetworkConnectivity
      request.requiresExternalPower = false
      return request
    case .appRefresh:
      return BGAppRefreshTaskRequest(identifier: identifier)
    }
  }
}

struct BackgroundTaskScheduler: Sendable {
  typealias Completion = @Sendable (Bool) -> Void

  private static let log = Log.as("BackgroundTaskScheduler")

  private let identifier: String
  private let cadence: Duration
  private let taskType: BackgroundTaskType
  @PersistedThreadSafe private var lastAttempt: Date

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
      let type: String
      switch request {
      case is BGProcessingTaskRequest: type = "processing"
      case is BGAppRefreshTaskRequest: type = "refresh"
      default: type = "unknown"
      }
      return "  - \(request.identifier) (\(type), earliest: \(date))"
    }
    .joined(separator: "\n  ")
  }

  init(
    identifier: String,
    cadence: Duration,
    taskType: BackgroundTaskType
  ) {
    self.identifier = identifier
    self.cadence = cadence
    self.taskType = taskType
    _lastAttempt = PersistedThreadSafe(
      wrappedValue: .distantPast,
      "BackgroundTaskScheduler.lastAttempt.\(identifier)"
    )

    Self.log.debug("BackgroundTaskScheduler with identifier: \(identifier)")
  }

  func register(executionTask: @escaping @Sendable (Completion) async -> Void) {
    Once.run(identifier) {
      Self.log.info("register() called for: \(identifier)")

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

        scheduleNextIfNeeded()
        bgTask = Task(priority: .background) { await executionTask(complete) }
      }

      Self.log.info(
        """
        BGTaskScheduler.shared.register returned: \(success)
        Registration for BackgroundTask: \(identifier) complete
        """
      )

      scheduleNextIfNeeded()
    }
  }

  func scheduleNextIfNeeded() {
    let elapsed = Date.now.timeIntervalSince(lastAttempt)
    guard elapsed >= cadence.asTimeInterval else {
      Self.log.debug(
        "scheduleNextIfNeeded: throttled for \(identifier), last attempt \(Int(elapsed))s ago"
      )
      return
    }

    BGTaskScheduler.shared.getPendingTaskRequests { [self] requests in
      let hasPending = requests.contains { $0.identifier == identifier }
      if hasPending {
        Self.log.debug("scheduleNextIfNeeded: task already pending for \(identifier), skipping")
        return
      }

      Self.log.debug("scheduleNextIfNeeded: no pending task for \(identifier), scheduling")
      scheduleNext()
    }
  }

  private func scheduleNext() {
    Self.log.debug("scheduleNext() called for: \(identifier)")

    let request = taskType.makeRequest(identifier: identifier)
    request.earliestBeginDate = Date.now.advanced(by: cadence.asTimeInterval)

    lastAttempt = .now

    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      Self.log.caughtError("scheduleNext: failed to submit background task '\(identifier)'", error)
      return
    }

    Self.log.debug(
      """
      scheduled next background task: \(identifier)
        cadence: \(cadence)
        earliest begin date: \(request.earliestBeginDate?.description ?? "nil")
      """
    )

    confirmAndLogPendingTask()
  }

  func confirmAndLogPendingTask() {
    guard lastAttempt != .distantPast else {
      return
    }

    BGTaskScheduler.shared.getPendingTaskRequests { [self] requests in
      let hasPending = requests.contains { $0.identifier == identifier }
      if hasPending {
        Self.log.debug("Pending task verified for '\(identifier)'")
      } else {
        Self.log.error(
          """
          Expected a pending task for '\(identifier)' but none found — \
          last scheduling attempt: \(lastAttempt.formatted())
          """
        )
      }
    }
  }
}
