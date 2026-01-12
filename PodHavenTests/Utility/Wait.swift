// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Tagged
import Testing

@testable import PodHaven

enum Wait {
  @discardableResult
  static func forValue<T: Sendable>(
    maxAttempts: Int = 250,
    delay: Duration = .milliseconds(10),
    _ block: @Sendable @escaping () async throws -> T?
  ) async throws -> T {
    var attempts = 0
    while attempts < maxAttempts {
      if let value = try await block() { return value }
      try await Task.sleep(for: delay)
      attempts += 1
    }
    throw TestError.waitForValueFailure(String(describing: T.self))
  }

  static func until(
    maxAttempts: Int = 250,
    delay: Duration = .milliseconds(10),
    _ block: @Sendable @escaping () async throws -> Bool,
    _ errorMessage: @Sendable @escaping () async throws -> String
  ) async throws {
    var attempts = 0
    while attempts < maxAttempts {
      if try await block() { return }
      try await Task.sleep(for: delay)
      attempts += 1
    }
    throw TestError.waitUntilFailure(try await errorMessage())
  }
}
