// Copyright Justin Bishop, 2026

import BackgroundTasks
import ConcurrencyExtras
import Foundation

protocol BGTaskHandling: Sendable {
  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void)
  func setTaskCompleted(success: Bool)
}

protocol BGTaskScheduling: Sendable {
  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (any BGTaskHandling) -> Void
  ) -> Bool

  func submit(_ taskRequest: BGTaskRequest) throws

  func cancel(taskRequestWithIdentifier identifier: String)

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  )
}

// BGTaskScheduler.shared is a process-wide singleton safe to use from any thread,
// but BGTaskScheduler doesn't declare Sendable conformance for its closures.
// This wrapper provides the Sendable conformance the protocol requires.
private struct SystemBGTask: BGTaskHandling {
  private let task: UncheckedSendable<BGTask>

  init(task: BGTask) {
    self.task = UncheckedSendable(task)
  }

  func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
    task.value.expirationHandler = handler
  }

  func setTaskCompleted(success: Bool) {
    task.value.setTaskCompleted(success: success)
  }
}

struct SystemBGTaskScheduler: BGTaskScheduling {
  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (any BGTaskHandling) -> Void
  ) -> Bool {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier,
      using: queue,
      launchHandler: { launchHandler(SystemBGTask(task: $0)) }
    )
  }

  func submit(_ taskRequest: BGTaskRequest) throws {
    try BGTaskScheduler.shared.submit(taskRequest)
  }

  func cancel(taskRequestWithIdentifier identifier: String) {
    BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
  }

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  ) {
    BGTaskScheduler.shared.getPendingTaskRequests(completionHandler: completionHandler)
  }
}
