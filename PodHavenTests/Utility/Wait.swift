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
        let startedAt = ContinuousClock.now
        var finalSleepStarted: ContinuousClock.Instant?
        while attempts < maxAttempts {
          if let value = try await block() { return value }
          if attempts == maxAttempts - 1 { finalSleepStarted = .now }
          try await Task.sleep(for: delay)
          attempts += 1
        }
        reportTimeout(startedAt: startedAt, finalSleepStarted: finalSleepStarted)
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
        let startedAt = ContinuousClock.now
        var finalSleepStarted: ContinuousClock.Instant?
        while attempts < maxAttempts {
          if try await block() { return }
          if attempts == maxAttempts - 1 { finalSleepStarted = .now }
          try await Task.sleep(for: delay)
          attempts += 1
        }
        reportTimeout(startedAt: startedAt, finalSleepStarted: finalSleepStarted)
        throw TestError.waitUntilFailure(try await errorMessage())
      }
      try await group.next()!
    }
  }

  private static func reportTimeout(
    startedAt: ContinuousClock.Instant,
    finalSleepStarted: ContinuousClock.Instant?
  ) {
    guard let test = Test.current else { return }
    let id = String(describing: test.id)
    guard
      [
        "backgroundingCancelsSleepingForegroundLoop",
        "deletionOwnsCleanupOfSuspendedTargetPlaybackLoad",
        "extensionlessDownloadUsesMP3StagingSuffix",
        "persistentCandidateObservationFailureSurfacesFailedAcrossReappear",
      ]
      .contains(where: id.contains)
    else { return }
    let now = ContinuousClock.now
    let finalSleep = finalSleepStarted?.duration(to: now).description ?? "none"
    print(
      "Issue676WaitTimeout test=\(id) waitDuration=\(startedAt.duration(to: now)) finalSleepDuration=\(finalSleep) unixSeconds=\(Date().timeIntervalSince1970)"
    )
  }
}
