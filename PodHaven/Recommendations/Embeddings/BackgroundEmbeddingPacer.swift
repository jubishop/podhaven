// Copyright Justin Bishop, 2026

import Foundation

actor BackgroundEmbeddingPacer {
  private static let unpacedWorkAllowance: Duration = .seconds(30)
  private static let targetWorkUtilization = 0.6

  private let clockNow: @Sendable () -> ContinuousClock.Instant
  private let sleeper: any Sleepable
  private let startedAt: ContinuousClock.Instant
  private var accumulatedWork: Duration = .zero

  init(
    clockNow: @escaping @Sendable () -> ContinuousClock.Instant,
    sleeper: any Sleepable
  ) {
    self.clockNow = clockNow
    self.sleeper = sleeper
    startedAt = clockNow()
  }

  func waitBeforeNextWork() async throws -> ContinuousClock.Instant {
    try Task.checkCancellation()
    guard accumulatedWork >= Self.unpacedWorkAllowance else { return clockNow() }

    let targetElapsed = Duration.seconds(
      accumulatedWork.asTimeInterval / Self.targetWorkUtilization
    )
    let elapsed = clockNow() - startedAt
    if targetElapsed > elapsed {
      try await sleeper.sleep(for: targetElapsed - elapsed)
    }
    try Task.checkCancellation()
    return clockNow()
  }

  func recordWork(since workStartedAt: ContinuousClock.Instant) {
    accumulatedWork += clockNow() - workStartedAt
  }
}
