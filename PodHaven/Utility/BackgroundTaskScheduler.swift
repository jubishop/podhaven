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

enum BackgroundTaskSchedulingMode: Sendable {
  case periodic
  case onDemand(hasWork: @Sendable () -> Bool)
}

enum BackgroundTaskExpirationBehavior: Sendable {
  case completeImmediately
  case awaitCancellation
}

struct BackgroundTaskScheduler: Sendable {
  typealias Completion = @Sendable (Bool) -> Void

  private enum ExecutionState: Sendable {
    case waiting
    case running(Task<Void, Never>)
    case expired
    case completed(Bool)
  }

  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler

  private static let log = Log.as("BackgroundTaskScheduler")

  private let identifier: String
  private let cadence: Duration
  private let taskType: BackgroundTaskType
  private let schedulingMode: BackgroundTaskSchedulingMode
  private let expirationBehavior: BackgroundTaskExpirationBehavior
  private let activeExecutions = ThreadSafe<[UUID: Task<Void, Never>]>([:])

  private var shouldSchedule: Bool {
    switch schedulingMode {
    case .periodic: true
    case .onDemand(let hasWork): hasWork()
    }
  }

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
    taskType: BackgroundTaskType,
    schedulingMode: BackgroundTaskSchedulingMode = .periodic,
    expirationBehavior: BackgroundTaskExpirationBehavior = .completeImmediately
  ) {
    self.identifier = identifier
    self.cadence = cadence
    self.taskType = taskType
    self.schedulingMode = schedulingMode
    self.expirationBehavior = expirationBehavior

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

        let executionState = ThreadSafe(ExecutionState.waiting)
        let complete: Completion = { [executionState, task] success in
          let completionResult: Bool? = executionState { state in
            switch state {
            case .waiting, .running:
              state = .completed(success)
              return success
            case .expired:
              state = .completed(false)
              return false
            case .completed:
              return nil
            }
          }
          if let completionResult {
            task.setTaskCompleted(success: completionResult)
          }
        }

        task.setExpirationHandler {
          Self.log.debug("handle: expiration triggered, cancelling running task for: \(identifier)")

          let expirationAction: (runningTask: Task<Void, Never>?, completesImmediately: Bool) =
            executionState { state in
              switch state {
              case .waiting:
                switch expirationBehavior {
                case .completeImmediately:
                  state = .completed(false)
                  return (nil, true)
                case .awaitCancellation:
                  state = .expired
                  return (nil, false)
                }
              case .running(let task):
                switch expirationBehavior {
                case .completeImmediately:
                  state = .completed(false)
                  return (task, true)
                case .awaitCancellation:
                  state = .expired
                  return (task, false)
                }
              case .expired, .completed:
                return (nil, false)
              }
            }
          if let runningTask = expirationAction.runningTask {
            runningTask.cancel()
          }
          if expirationAction.completesImmediately {
            task.setTaskCompleted(success: false)
          }
        }

        scheduleNext()
        let startLatch = AsyncLatch<Void>()
        let executionToken = UUID()
        let runningTask = Task {
          defer {
            activeExecutions { $0[executionToken] = nil }
          }
          do {
            try Task.checkCancellation()
            try await startLatch.wait()
            try Task.checkCancellation()
            await executionTask(complete)
          } catch is CancellationError {
            complete(false)
            return
          } catch {
            Self.log.caughtError("Failed to start background task \(identifier)", error)
            complete(false)
            return
          }
          if Task.isCancelled {
            complete(false)
          }
        }
        activeExecutions { $0[executionToken] = runningTask }
        let shouldCancelBeforeStart = executionState { state in
          switch state {
          case .waiting:
            state = .running(runningTask)
            return false
          case .expired, .completed(false):
            return true
          case .running:
            Assert.fatal("Background task \(identifier) installed its execution task twice")
          case .completed(true):
            Assert.fatal("Background task \(identifier) completed before execution was installed")
          }
        }
        if shouldCancelBeforeStart {
          runningTask.cancel()
        }
        startLatch.open()
      }

      guard success else {
        Self.log.error("register failed for BackgroundTask: \(identifier)")
        return
      }

      Self.log.info("Registration for BackgroundTask: \(identifier) complete")
      scheduleNext()
    }
  }

  func cancelRunningTasks() {
    let tasks = Array(activeExecutions().values)
    for task in tasks { task.cancel() }
  }

  func scheduleNext() {
    guard shouldSchedule else {
      bgTaskScheduler.cancel(taskRequestWithIdentifier: identifier)
      Self.log.debug("scheduleNext: no work for \(identifier), cancelled pending request")
      return
    }

    bgTaskScheduler.getPendingTaskRequests { requests in
      guard shouldSchedule else {
        bgTaskScheduler.cancel(taskRequestWithIdentifier: identifier)
        Self.log.debug("scheduleNext: work cleared for \(identifier), cancelled pending request")
        return
      }
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

      if !shouldSchedule {
        bgTaskScheduler.cancel(taskRequestWithIdentifier: identifier)
        Self.log.debug(
          "scheduleNext: work cleared while submitting \(identifier), cancelled request"
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
