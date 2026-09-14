// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

// Polling requests .background, but awaiting the task group can elevate it
// to the caller's priority. Use completion signals for low-priority workers.
// Blocks that spawn work can request a higher priority for that child work.
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
