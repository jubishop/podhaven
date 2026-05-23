// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

// Direct tests for the shared scoring orchestration: snapshot-keyed skip,
// cancel-and-restart, stale-drop, the `$scoringRevision` trigger, nil-snapshot
// no-op, cache retention across `cancel()`, and the failure path.
@Suite("of RecommendationScoringCoordinator tests", .container)
@MainActor final class RecommendationScoringCoordinatorTests {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine

  private struct Snapshot: Equatable, Sendable {
    var input: Int
    var revision: Int
  }

  // Controllable score backend: captures `input` at pass start, optionally
  // suspends on a gate, then returns that captured value.
  @MainActor private final class Probe {
    @DynamicInjected(\.recommendationEngine) private var recommendationEngine

    var input = 1
    var returnsNilSnapshot = false
    var cacheable = true
    var returnsCancelled = false

    private(set) var scoreStarts = 0
    private(set) var willScoreCount = 0
    private(set) var applied: [Int] = []

    private var gateOpen = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func closeGate() { gateOpen = false }

    func openGate() {
      gateOpen = true
      let pending = waiters
      waiters = []
      for waiter in pending { waiter.resume() }
    }

    func snapshot() -> Snapshot? {
      guard !returnsNilSnapshot else { return nil }
      return Snapshot(input: input, revision: recommendationEngine.scoringRevision)
    }

    func score() async -> RecommendationScoringCoordinator<Snapshot, Int>.ScoreResult {
      let captured = input
      scoreStarts += 1
      if !gateOpen {
        await withCheckedContinuation { waiters.append($0) }
      }
      if returnsCancelled { return .cancelled }
      return cacheable ? .cacheable(captured) : .uncacheable(captured)
    }

    func willScore() { willScoreCount += 1 }
    func apply(_ result: Int) { applied.append(result) }
  }

  private func makeCoordinator(
    _ probe: Probe
  ) -> RecommendationScoringCoordinator<Snapshot, Int> {
    RecommendationScoringCoordinator<Snapshot, Int>(
      makeSnapshot: { probe.snapshot() },
      willScore: { probe.willScore() },
      score: { await probe.score() },
      apply: { probe.apply($0) }
    )
  }

  @Test("refresh runs a scoring pass and applies the result")
  func refreshScoresAndApplies() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 7
    coordinator.refresh()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [7] },
      { @MainActor in "Expected the pass to apply [7], got \(probe.applied)." }
    )
    #expect(probe.scoreStarts == 1)
    #expect(probe.willScoreCount == 1)
  }

  @Test("an unchanged snapshot skips re-scoring and re-applies the cached result")
  func unchangedSnapshotSkipsRescore() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 3
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [3] },
      { @MainActor in "Expected the first pass to apply [3], got \(probe.applied)." }
    )

    coordinator.refresh()

    #expect(probe.applied == [3, 3])
    #expect(probe.scoreStarts == 1)
    // A cache hit must not flash the surface's "computing" indicator.
    #expect(probe.willScoreCount == 1)
  }

  @Test("a changed snapshot re-scores")
  func changedSnapshotRescores() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 1
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [1] },
      { @MainActor in "Expected first pass to apply [1], got \(probe.applied)." }
    )

    probe.input = 2
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [1, 2] },
      { @MainActor in "Expected second pass to apply [1, 2], got \(probe.applied)." }
    )
    #expect(probe.scoreStarts == 2)
  }

  @Test("a cache-missing refresh cancels the in-flight pass so only the latest applies")
  func cacheMissingRefreshCancelsInFlightPass() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)
    probe.closeGate()

    probe.input = 1
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 1 },
      { @MainActor in "Expected the first pass to start." }
    )

    probe.input = 2
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 2 },
      { @MainActor in "Expected the second pass to start." }
    )

    probe.openGate()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [2] },
      { @MainActor in
        "Expected only the latest pass to apply [2], got \(probe.applied)."
      }
    )
  }

  @Test("a pass whose snapshot goes stale mid-flight drops its result")
  func stalePassDropsResult() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)
    probe.closeGate()

    probe.input = 1
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 1 },
      { @MainActor in "Expected the pass to start." }
    )

    // Inputs move on with no refresh, so the in-flight task is not cancelled —
    // only the stale-drop guard can discard the now-stale result.
    probe.input = 2
    probe.openGate()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 1 },
      { @MainActor in "Sanity: the stale pass must not be re-run." }
    )
    #expect(probe.applied.isEmpty)
  }

  @Test("a $scoringRevision bump triggers a re-score")
  func scoringRevisionBumpTriggersRescore() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)
    coordinator.startObservingScoringRevision()

    probe.input = 5
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [5] },
      { @MainActor in "Expected the initial pass to apply [5], got \(probe.applied)." }
    )

    recommendationEngine.$scoringRevision.update { $0 += 1 }

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 2 },
      { @MainActor in
        "Expected the $scoringRevision bump to trigger a second pass."
      }
    )
    #expect(probe.applied == [5, 5])

    coordinator.cancel()
  }

  @Test("a nil snapshot makes refresh a no-op")
  func nilSnapshotRefreshIsNoOp() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.returnsNilSnapshot = true
    coordinator.refresh()

    // Give any erroneously-spawned pass room to run before asserting.
    for _ in 0..<5 { await Task.yield() }
    #expect(probe.scoreStarts == 0)
    #expect(probe.willScoreCount == 0)
    #expect(probe.applied.isEmpty)

    probe.returnsNilSnapshot = false
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [1] },
      { @MainActor in "Expected scoring to resume once a snapshot is available." }
    )
  }

  @Test("cancel retains the cache so a later unchanged refresh applies without re-scoring")
  func cancelRetainsCache() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 9
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [9] },
      { @MainActor in "Expected the pass to apply [9], got \(probe.applied)." }
    )

    coordinator.cancel()
    coordinator.refresh()

    #expect(probe.applied == [9, 9])
    #expect(probe.scoreStarts == 1)
  }

  @Test(
    "an .uncacheable result applies but skips caching so the next same-snapshot refresh re-scores"
  )
  func uncacheableResultSkipsCacheSoFutureRefreshRecomputes() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 4
    probe.cacheable = false
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [4] },
      { @MainActor in
        "Expected the uncacheable pass to apply [4], got \(probe.applied)."
      }
    )

    // Same snapshot, but the prior pass was uncacheable — refresh must re-run
    // score() instead of replaying a cached result.
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [4, 4] },
      { @MainActor in
        "Expected the same-snapshot refresh to recompute and apply [4, 4], got \(probe.applied)."
      }
    )
    #expect(probe.scoreStarts == 2)

    // Returning .cacheable lets the next pass settle into the cache; a
    // subsequent same-snapshot refresh then hits without recomputing.
    probe.cacheable = true
    probe.input = 5
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [4, 4, 5] },
      { @MainActor in
        "Expected the cacheable pass to apply [4, 4, 5], got \(probe.applied)."
      }
    )

    coordinator.refresh()
    #expect(probe.applied == [4, 4, 5, 5])
    #expect(probe.scoreStarts == 3)
  }

  @Test("a .cancelled result is dropped without applying or caching")
  func cancelledResultIsDroppedWithoutSideEffects() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)

    probe.input = 8
    probe.returnsCancelled = true
    coordinator.refresh()

    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 1 },
      { @MainActor in "Expected the cancelled pass to run before checking side effects." }
    )
    for _ in 0..<5 { await Task.yield() }

    #expect(probe.applied.isEmpty)

    // Same snapshot, but the prior pass was .cancelled — refresh must re-run
    // score() instead of replaying a cached result.
    probe.returnsCancelled = false
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [8] },
      { @MainActor in
        "Expected the same-snapshot refresh to recompute after .cancelled, got \(probe.applied)."
      }
    )
    #expect(probe.scoreStarts == 2)
  }

  @Test("refresh is a no-op while an in-flight pass already covers the current snapshot")
  func refreshSkipsWhileInFlightMatches() async throws {
    let probe = Probe()
    let coordinator = makeCoordinator(probe)
    probe.closeGate()

    probe.input = 21
    coordinator.refresh()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.scoreStarts == 1 },
      { @MainActor in "Expected the in-flight pass to start." }
    )

    coordinator.refresh()

    // The in-flight pass matches the current snapshot, so the second call
    // must not cancel-and-restart it.
    #expect(probe.scoreStarts == 1)
    #expect(probe.willScoreCount == 1)

    probe.openGate()
    try await Wait.until(
      priority: .userInitiated,
      { @MainActor in probe.applied == [21] },
      { @MainActor in "Expected the original pass to apply [21], got \(probe.applied)." }
    )
    #expect(probe.scoreStarts == 1)
  }
}
