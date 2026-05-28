// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

// Shared scoring orchestration: revision observation, snapshot-keyed cache,
// and cancel-and-restart tasks.
//
// `Snapshot` is the change-detection key. It must embed `scoringRevision` and
// every input read by `score` — otherwise a cache hit will replay a stale
// result for inputs that have since moved on.
//
// A `nil` snapshot makes `refresh()` a no-op (use when the surface has no
// scoring inputs to key on, e.g. an unset selection).
//
// `score` is non-throwing: each closure owns its full error policy and maps
// outcomes to `ScoreResult`. `.cacheable` memoizes for future
// identical-snapshot hits; `.uncacheable` applies once without caching (use
// when the pass ran against inputs the `Snapshot` doesn't fully capture, e.g.
// embedding assets that hadn't finished downloading — caching would replay
// the empty result on the next refresh even after the assets land);
// `.cancelled` drops the pass without applying or caching (use when the
// closure catches `CancellationError` or otherwise needs to abort silently).
//
// Cache holds only the most-recently-cached snapshot's result; oscillating
// between two snapshots re-scores each visit.
//
// `apply` may fire synchronously inside `refresh()` on a cache hit, or
// asynchronously from the in-flight task on a fresh pass; callers must be
// safe in both contexts.
@MainActor
final class RecommendationScoringCoordinator<Snapshot: Equatable & Sendable, Score: Sendable> {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.taskPriority) private var taskPriority

  private static var log: Logger { Log.as(LogSubsystem.Recommendations.coordinator) }

  enum ScoreResult: Sendable {
    case cacheable(Score)
    case uncacheable(Score)
    case cancelled
  }

  private let makeSnapshot: @MainActor () -> Snapshot?
  private let score: @MainActor () async -> ScoreResult
  private let apply: @MainActor (Score) -> Void
  private let refreshOnAssetsLoaded: Bool

  private var revisionTask: Task<Void, Never>?
  private var assetsLoadedTask: Task<Void, Never>?
  private var inFlight: (task: Task<Void, Never>, snapshot: Snapshot, generation: Int)?
  private var cached: (snapshot: Snapshot, score: Score)?
  private var nextGeneration = 0

  init(
    makeSnapshot: @escaping @MainActor () -> Snapshot?,
    score: @escaping @MainActor () async -> ScoreResult,
    apply: @escaping @MainActor (Score) -> Void,
    refreshOnAssetsLoaded: Bool = false
  ) {
    self.makeSnapshot = makeSnapshot
    self.score = score
    self.apply = apply
    self.refreshOnAssetsLoaded = refreshOnAssetsLoaded
  }

  // Idempotent. Starts the `$scoringRevision` observation and, when
  // `refreshOnAssetsLoaded` is true, the one-shot assets-loaded observation.
  // Builds the revision stream synchronously so a revision emitted before
  // the consuming task is scheduled is queued, not dropped.
  func startObservations() {
    startRevisionTaskIfNeeded()
    startAssetsLoadedTaskIfNeeded()
  }

  private func startRevisionTaskIfNeeded() {
    if let revisionTask, !revisionTask.isCancelled { return }
    let scoringRevisions = recommendationEngine.$scoringRevision.stream().dropFirst()
    revisionTask = Task(priority: taskPriority(.utility)) { [weak self] in
      for await _ in scoringRevisions {
        guard let self, !Task.isCancelled else { return }
        refresh()
      }
    }
  }

  // Saved-side surfaces are naturally a no-op here: their snapshot doesn't
  // change when the latch fires, so the refresh hits the cache. Only unsaved
  // scorers — which `.uncacheable` while assets are still downloading — see
  // recomputation, producing real similarity scores against the loaded model.
  private func startAssetsLoadedTaskIfNeeded() {
    guard refreshOnAssetsLoaded else { return }
    if let assetsLoadedTask, !assetsLoadedTask.isCancelled { return }
    assetsLoadedTask = Task(priority: taskPriority(.utility)) { [weak self] in
      do {
        try await Container.shared.contextualEmbedding().assetsLoaded.wait()
      } catch {
        // Cancellation path. `cancel()` already nilled the property; the
        // natural-completion clear below would otherwise clobber a task
        // installed by an intervening re-bind.
        return
      }
      guard let self, !Task.isCancelled else { return }
      refresh()
      assetsLoadedTask = nil
    }
  }

  // Gated on snapshot: skips when the snapshot is already cached or covered
  // by an in-flight pass. Since `Snapshot` must embed every input read by
  // `score`, an identical-snapshot restart is always wasted work.
  func refresh() {
    guard let snapshot = makeSnapshot() else {
      Self.log.trace("refresh: skipped, nil snapshot")
      return
    }
    if let cached, cached.snapshot == snapshot {
      Self.log.trace("refresh: cache hit, applying")
      apply(cached.score)
      return
    }
    guard inFlight?.snapshot != snapshot else {
      Self.log.trace("refresh: snapshot matches in-flight, skipping")
      return
    }
    Self.log.debug("refresh: new pass, generation=\(nextGeneration + 1)")
    inFlight?.task.cancel()
    nextGeneration += 1
    let generation = nextGeneration
    let task = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await runPass(for: snapshot, generation: generation)
    }
    inFlight = (task, snapshot, generation)
  }

  private func runPass(for snapshot: Snapshot, generation: Int) async {
    // Only clear when the generation still matches. A cancel→same-snapshot
    // refresh→cancel race can install a new task at the same snapshot before
    // this continuation resumes; a snapshot-only check would clobber the new
    // task's handle, leaving it unreachable from a subsequent cancel().
    defer {
      if inFlight?.generation == generation { inFlight = nil }
    }
    let result = await score()
    guard !Task.isCancelled else { return }
    // Stale-drop: inputs moved on while the pass was in flight.
    guard makeSnapshot() == snapshot else { return }
    switch result {
    case .cacheable(let score):
      cached = (snapshot, score)
      apply(score)
    case .uncacheable(let score):
      apply(score)
    case .cancelled:
      return
    }
  }

  func cancel() {
    revisionTask?.cancel()
    revisionTask = nil
    assetsLoadedTask?.cancel()
    assetsLoadedTask = nil
    inFlight?.task.cancel()
    inFlight = nil
  }
}
