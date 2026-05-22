// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// Shared scoring orchestration: revision observation, snapshot-keyed cache,
// and cancel-and-restart tasks. `Snapshot` is the change-detection key (must
// embed `scoringRevision` and every input read by `score`, or a cache hit
// will replay a stale result); `nil` no-ops the refresh.
@MainActor
final class RecommendationScoringCoordinator<Snapshot: Equatable & Sendable, Score: Sendable> {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.taskPriority) private var taskPriority

  private static var log: Logger { Log.as(LogSubsystem.Recommendations.coordinator) }

  private let makeSnapshot: @MainActor () -> Snapshot?
  private let willScore: @MainActor () -> Void
  private let score: @MainActor () async throws -> Score
  private let shouldCache: @MainActor () -> Bool
  private let apply: @MainActor (Score) -> Void
  private let onFailure: @MainActor (any Error) -> Void

  private var revisionTask: Task<Void, Never>?
  private var scoringTask: Task<Void, Never>?
  private var pendingSnapshot: Snapshot?
  private var cached: (snapshot: Snapshot, score: Score)?

  // - `willScore`: fires on a cache miss, before the pass spawns.
  // - `shouldCache`: gates caching after the pass returns. Return `false` for
  //   provisional results (e.g. embedding assets not yet downloaded) so they
  //   apply but don't stick after their inputs resolve.
  // - `onFailure`: fires only on a non-cancellation `score` error.
  init(
    makeSnapshot: @escaping @MainActor () -> Snapshot?,
    willScore: @escaping @MainActor () -> Void = {},
    score: @escaping @MainActor () async throws -> Score,
    shouldCache: @escaping @MainActor () -> Bool = { true },
    apply: @escaping @MainActor (Score) -> Void,
    onFailure: @escaping @MainActor (any Error) -> Void = { _ in }
  ) {
    self.makeSnapshot = makeSnapshot
    self.willScore = willScore
    self.score = score
    self.shouldCache = shouldCache
    self.apply = apply
    self.onFailure = onFailure
  }

  // Idempotent. Builds the stream synchronously so a revision emitted before
  // the consuming task is scheduled is queued, not dropped.
  func startObservingScoringRevision() {
    if let revisionTask, !revisionTask.isCancelled { return }
    let scoringRevisions = recommendationEngine.$scoringRevision.stream().dropFirst()
    revisionTask = Task(priority: taskPriority(.utility)) { [weak self] in
      for await _ in scoringRevisions {
        guard let self, !Task.isCancelled else { return }
        refresh()
      }
    }
  }

  func refresh() {
    guard let snapshot = makeSnapshot() else { return }
    if let cached, cached.snapshot == snapshot {
      apply(cached.score)
      return
    }
    willScore()
    scoringTask?.cancel()
    pendingSnapshot = snapshot
    scoringTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await runPass(for: snapshot)
    }
  }

  // Gated entry point: skip when the current snapshot is already either cached
  // or being processed by an in-flight pass. Use this from a caller that may
  // run alongside another path that already kicked the refresh, to avoid
  // redundantly cancel-and-restarting an identical-input pass.
  func refreshIfNeeded() {
    guard let snapshot = makeSnapshot() else { return }
    if let cached, cached.snapshot == snapshot {
      apply(cached.score)
      return
    }
    guard pendingSnapshot != snapshot else { return }
    refresh()
  }

  private func runPass(for snapshot: Snapshot) async {
    // Only clear when no newer pass has taken over `pendingSnapshot`; a later
    // refresh() may have replaced it with a different snapshot.
    defer {
      if pendingSnapshot == snapshot { pendingSnapshot = nil }
    }
    do {
      let result = try await score()
      guard !Task.isCancelled else { return }
      // Stale-drop: inputs moved on while the pass was in flight.
      guard makeSnapshot() == snapshot else { return }
      if shouldCache() { cached = (snapshot, result) }
      apply(result)
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled else { return }
      // Log at the top of the stack so a surface that omits `onFailure`
      // never silently drops the error.
      Self.log.caughtError("scoring pass failed", error)
      onFailure(error)
    }
  }

  func cancel() {
    revisionTask?.cancel()
    revisionTask = nil
    scoringTask?.cancel()
    scoringTask = nil
    pendingSnapshot = nil
  }
}
