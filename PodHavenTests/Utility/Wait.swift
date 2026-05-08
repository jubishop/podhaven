// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

// Polling defaults to .background priority so it never starves the
// .utility (or higher) production tasks whose effects it waits for.
// Tests whose `block` itself spawns work (via `Task {}` etc. inheriting
// from the poller) can pass a higher `priority` to avoid starving that
// child work at the cooperative pool's lowest tier.
enum Wait {
  @discardableResult
  static func forValue<T: Sendable>(
    maxAttempts: Int = 1000,
    delay: Duration = .milliseconds(10),
    priority: TaskPriority = .background,
    _ block: @Sendable @escaping () async throws -> T?
  ) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask(priority: priority) {
        var attempts = 0
        while attempts < maxAttempts {
          if let value = try await block() { return value }
          try await Task.sleep(for: delay)
          attempts += 1
        }
        throw TestError.waitForValueFailure(String(describing: T.self))
      }
      return try await group.next()!
    }
  }

  static func until(
    maxAttempts: Int = 1000,
    delay: Duration = .milliseconds(10),
    priority: TaskPriority = .background,
    _ block: @Sendable @escaping () async throws -> Bool,
    _ errorMessage: @Sendable @escaping () async throws -> String
  ) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask(priority: priority) {
        var attempts = 0
        while attempts < maxAttempts {
          if try await block() { return }
          try await Task.sleep(for: delay)
          attempts += 1
        }
        throw TestError.waitUntilFailure(try await errorMessage())
      }
      try await group.next()!
    }
  }
}
