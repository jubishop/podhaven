// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Shared recommendation-score orchestration for the view-model surfaces that
// sort or display engine scores: EpisodesListViewModel, EpisodeDetailViewModel,
// and PodcastRecommendationScorer.
//
// It single-sources the "what triggers a re-score" contract. Every surface
// re-scores on the engine's `$scoringRevision` stream through this one type,
// so a new scoring input wired into the engine cannot silently miss a surface.
// Beyond the revision observation it owns the snapshot-keyed skip and the
// cancel-and-restart task machinery; a surface supplies only its snapshot
// shape, a score closure, and an apply closure.
//
// `Snapshot` is an `Equatable` change-detection key — it embeds the engine's
// `scoringRevision` plus whatever per-surface inputs scoring reads. A `nil`
// snapshot means "nothing to score right now"; such a refresh no-ops without
// touching the cache. `Result` is the per-surface score payload, retained
// across `cancel()` so a re-selection with unchanged inputs applies instantly.
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

  // `willScore` runs synchronously on a cache-missing `refresh()`, before the
  // pass is spawned, so a surface can flip its "computing" indicator without
  // it flickering on a cache hit. `onFailure` runs only when `score` throws a
  // non-cancellation error.
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

  // Begin observing `$scoringRevision`; each emission triggers a `refresh()`.
  // Idempotent — a live observation is left in place. The stream is built
  // synchronously so a revision emitted before the consuming task is scheduled
  // is queued, not dropped.
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

  // Re-score if the current snapshot differs from the last completed pass;
  // re-apply the cached result if it does not. A cache-missing refresh cancels
  // any in-flight pass and restarts, so the latest inputs always win.
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

  // Cancel in-flight observation and scoring. The score cache is retained, so
  // a later `refresh()` with unchanged inputs applies without recomputing.
  func cancel() {
    revisionTask?.cancel()
    revisionTask = nil
    scoringTask?.cancel()
    scoringTask = nil
  }
}
