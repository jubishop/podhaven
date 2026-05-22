// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Shared recommendation-score orchestration for EpisodesListViewModel,
// EpisodeDetailViewModel, and PodcastRecommendationScorer. It owns the engine's
// `$scoringRevision` observation, the snapshot-keyed skip, and the
// cancel-and-restart task machinery, so the set of re-score triggers cannot
// drift per surface.
//
// `Snapshot` is an `Equatable` change-detection key embedding `scoringRevision`;
// a `nil` snapshot no-ops the refresh. `Result` is the per-surface score
// payload, retained across `cancel()`.
@MainActor
final class RecommendationScoringCoordinator<Snapshot: Equatable & Sendable, Result: Sendable> {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.taskPriority) private var taskPriority

  private let makeSnapshot: @MainActor () -> Snapshot?
  private let willScore: @MainActor () -> Void
  private let score: @MainActor () async throws -> Result
  private let apply: @MainActor (Result) -> Void
  private let onFailure: @MainActor (any Error) -> Void

  private var revisionTask: Task<Void, Never>?
  private var scoringTask: Task<Void, Never>?
  private var cached: (snapshot: Snapshot, result: Result)?

  // `willScore` fires on a cache miss before the pass spawns; `onFailure` only
  // on a non-cancellation `score` error.
  init(
    makeSnapshot: @escaping @MainActor () -> Snapshot?,
    willScore: @escaping @MainActor () -> Void = {},
    score: @escaping @MainActor () async throws -> Result,
    apply: @escaping @MainActor (Result) -> Void,
    onFailure: @escaping @MainActor (any Error) -> Void = { _ in }
  ) {
    self.makeSnapshot = makeSnapshot
    self.willScore = willScore
    self.score = score
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
      apply(cached.result)
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
      cached = (snapshot, result)
      apply(result)
    } catch is CancellationError {
    } catch {
      guard !Task.isCancelled else { return }
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
