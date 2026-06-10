// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Direct tests for the gate contract: the bootstrap emit seeds state without
// firing the transition callback, close → open fires it, a rebuild that yields
// no context downgrades .ready, awaitReady() waits through .unavailable, and
// re-arming refreshes the callback so the latest one wins.
@Suite("of ScoringReadinessGate tests", .container)
@MainActor final class ScoringReadinessGateTests {
  @DynamicInjected(\.recommendationEngine) private var engine

  private var transitions = 0
  private var staleTransitions = 0
  private var awaitReadyResumed = false

  // Mirrors RecommendationEngine's rebuild signal order: the context flag
  // lands first, then the revision bump notifies subscribers.
  private func rebuild(open: Bool) {
    engine.$hasScoringContext.new(open)
    engine.$scoringRevision.update { $0 += 1 }
  }

  // MARK: - Test: Bootstrap Seeds Ready Without Firing

  @Test("bootstrap emit seeds .ready without firing the transition callback")
  func bootstrapSeedsReadyWithoutFiring() async throws {
    rebuild(open: true)
    let gate = ScoringReadinessGate()
    gate.ensureWatching { self.transitions += 1 }
    try await Wait.until(
      { @MainActor in gate.state == .ready },
      { @MainActor in "Expected bootstrap to seed .ready; got \(gate.state)" }
    )
    #expect(transitions == 0)
  }

  // MARK: - Test: Bootstrap Seeds Unavailable

  @Test("bootstrap emit seeds .unavailable when the engine finished a rebuild cold")
  func bootstrapSeedsUnavailable() async throws {
    rebuild(open: false)
    let gate = ScoringReadinessGate()
    gate.ensureWatching { self.transitions += 1 }
    try await Wait.until(
      { @MainActor in gate.state == .unavailable },
      { @MainActor in "Expected bootstrap to seed .unavailable; got \(gate.state)" }
    )
    #expect(transitions == 0)
  }

  // MARK: - Test: Close To Open Fires Callback

  @Test("close → open transition fires the callback and lands .ready")
  func closeToOpenFiresCallback() async throws {
    rebuild(open: false)
    let gate = ScoringReadinessGate()
    gate.ensureWatching { self.transitions += 1 }
    try await Wait.until(
      { @MainActor in gate.state == .unavailable },
      { @MainActor in "Expected bootstrap to seed .unavailable; got \(gate.state)" }
    )

    rebuild(open: true)
    try await Wait.until(
      { @MainActor in self.transitions == 1 },
      { @MainActor in "Expected one transition fire; got \(self.transitions)" }
    )
    #expect(gate.state == .ready)
  }

  // MARK: - Test: Cooling Downgrades Ready

  @Test("a rebuild that yields no context downgrades .ready to .unavailable")
  func coolingDowngradesReady() async throws {
    rebuild(open: true)
    let gate = ScoringReadinessGate()
    gate.ensureWatching { self.transitions += 1 }
    try await Wait.until(
      { @MainActor in gate.state == .ready },
      { @MainActor in "Expected bootstrap to seed .ready; got \(gate.state)" }
    )

    rebuild(open: false)
    try await Wait.until(
      { @MainActor in gate.state == .unavailable },
      { @MainActor in "Expected the cooled engine to downgrade; got \(gate.state)" }
    )
    #expect(transitions == 0)
  }

  // MARK: - Test: AwaitReady Waits Through Unavailable

  @Test("awaitReady() keeps waiting through .unavailable and returns on .ready")
  func awaitReadyWaitsThroughUnavailable() async throws {
    rebuild(open: false)
    let gate = ScoringReadinessGate()
    gate.ensureWatching {}
    try await Wait.until(
      { @MainActor in gate.state == .unavailable },
      { @MainActor in "Expected bootstrap to seed .unavailable; got \(gate.state)" }
    )

    Task {
      await gate.awaitReady()
      self.awaitReadyResumed = true
    }
    // Let the awaitReady task subscribe and process the replayed .unavailable;
    // returning on it would be the regression this pins.
    for _ in 0..<10 { await Task.yield() }
    #expect(!awaitReadyResumed)

    rebuild(open: true)
    try await Wait.until(
      { @MainActor in self.awaitReadyResumed },
      { @MainActor in "Expected awaitReady to resume once the engine warmed" }
    )
  }

  // MARK: - Test: Re-Arm Refreshes Callback

  @Test("re-arming refreshes the callback so the latest one wins")
  func reArmRefreshesCallback() async throws {
    rebuild(open: false)
    let gate = ScoringReadinessGate()
    gate.ensureWatching { self.staleTransitions += 1 }
    try await Wait.until(
      { @MainActor in gate.state == .unavailable },
      { @MainActor in "Expected bootstrap to seed .unavailable; got \(gate.state)" }
    )

    gate.ensureWatching { self.transitions += 1 }
    rebuild(open: true)
    try await Wait.until(
      { @MainActor in self.transitions == 1 },
      { @MainActor in "Expected the refreshed callback to fire; got \(self.transitions)" }
    )
    #expect(staleTransitions == 0)
  }
}
