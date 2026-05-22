// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// Shared recommendation-score orchestration for EpisodesListViewModel,
// EpisodeDetailViewModel, and PodcastRecommendationScorer. It owns the engine's
// `$scoringRevision` observation, the snapshot-keyed skip, and the
// cancel-and-restart task machinery, so the set of re-score triggers cannot
// drift per surface.
//
// `Snapshot` is an `Equatable` change-detection key embedding `scoringRevision`;
// a `nil` snapshot no-ops the refresh. `Score` is the per-surface score
// payload, retained across `cancel()`.
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
  private var cached: (snapshot: Snapshot, score: Score)?

  // `willScore` fires on a cache miss before the pass spawns; `shouldCache`
  // is checked after the pass returns to gate whether the result enters the
  // cache (a provisional result — e.g. embedding assets not yet downloaded —
  // applies but must not be cached or it would re-apply on the next refresh
  // even after the inputs that made it provisional resolved); `onFailure`
  // only on a non-cancellation `score` error.
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
    scoringTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await runPass(for: snapshot)
    }
  }

  private func runPass(for snapshot: Snapshot) async {
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
  }
}
