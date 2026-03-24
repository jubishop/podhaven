// Copyright Justin Bishop, 2025

import BackgroundTasks
import FactoryKit
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

  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler

  private static let log = Log.as("BackgroundTaskScheduler")

  private let identifier: String
  private let cadence: Duration
  private let taskType: BackgroundTaskType

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

    Self.log.debug("BackgroundTaskScheduler with identifier: \(identifier)")
  }

  func register(executionTask: @escaping @Sendable (Completion) async -> Void) {
    Once.run(identifier) {
      Self.log.info("register() called for: \(identifier)")

      let success = bgTaskScheduler.register(
        forTaskWithIdentifier: identifier,
        using: nil
      ) { task in
        Self.log.debug("iOS is executing the background task: \(identifier)")

        let didComplete = ThreadLock()
        let complete: Completion = { [didComplete, task] success in
          guard didComplete.claim() else { return }
          task.setTaskCompleted(success: success)
        }

        let bgTask = ThreadSafe<Task<Void, Never>?>(nil)
        task.setExpirationHandler { [complete] in
          Self.log.debug("handle: expiration triggered, cancelling running task for: \(identifier)")

          bgTask()?.cancel()
          complete(false)
        }

        scheduleNext()
        bgTask(Task { await executionTask(complete) })
      }

      guard success else {
        Self.log.error("register failed for BackgroundTask: \(identifier)")
        return
      }

      Self.log.info("Registration for BackgroundTask: \(identifier) complete")
      scheduleNext()
    }
  }

  func scheduleNext() {
    bgTaskScheduler.getPendingTaskRequests { requests in
      if requests.contains(where: { $0.identifier == identifier }) {
        Self.log.debug("scheduleNext: task already pending for \(identifier), skipping")
        return
      }

      let request = taskType.makeRequest(identifier: identifier)
      request.earliestBeginDate = Date.now.advanced(by: cadence.asTimeInterval)

      do {
        try bgTaskScheduler.submit(request)
      } catch {
        Self.log.caughtError(
          "scheduleNext: failed to submit background task '\(identifier)'",
          error
        )
        return
      }

      Self.log.debug(
        """
        scheduled next background task: \(identifier)
          cadence: \(cadence)
          earliest begin date: \(request.earliestBeginDate?.description ?? "nil")
        """
      )
    }
  }
}
