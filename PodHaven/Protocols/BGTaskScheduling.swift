// Copyright Justin Bishop, 2026

import BackgroundTasks
import Foundation

protocol BGTaskScheduling: Sendable {
  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (BGTask) -> Void
  ) -> Bool

  func submit(_ taskRequest: BGTaskRequest) throws

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  )
}

// BGTaskScheduler.shared is a process-wide singleton safe to use from any thread,
// but BGTaskScheduler doesn't declare Sendable conformance for its closures.
// This wrapper provides the Sendable conformance the protocol requires.
struct SystemBGTaskScheduler: BGTaskScheduling {
  @discardableResult
  func register(
    forTaskWithIdentifier identifier: String,
    using queue: DispatchQueue?,
    launchHandler: @escaping @Sendable (BGTask) -> Void
  ) -> Bool {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: identifier,
      using: queue,
      launchHandler: launchHandler
    )
  }

  func submit(_ taskRequest: BGTaskRequest) throws {
    try BGTaskScheduler.shared.submit(taskRequest)
  }

  func getPendingTaskRequests(
    completionHandler: @escaping @Sendable ([BGTaskRequest]) -> Void
  ) {
    BGTaskScheduler.shared.getPendingTaskRequests(completionHandler: completionHandler)
  }
}
