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
// `ScoreResult` chooses the caching policy per pass: `.cacheable` stores the
// result for future identical-snapshot hits; `.uncacheable` applies the
// result once without caching (use when the pass ran against inputs the
// `Snapshot` doesn't fully capture, e.g. embedding assets that hadn't
// finished downloading — caching would replay the empty result on the next
// refresh even after the assets land).
@MainActor
final class RecommendationScoringCoordinator<Snapshot: Equatable & Sendable, Score: Sendable> {
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.taskPriority) private var taskPriority

  private static var log: Logger { Log.as(LogSubsystem.Recommendations.coordinator) }

  enum ScoreResult: Sendable {
    case cacheable(Score)
    case uncacheable(Score)
  }

  private let makeSnapshot: @MainActor () -> Snapshot?
  private let willScore: @MainActor () -> Void
  private let score: @MainActor () async throws -> ScoreResult
  private let apply: @MainActor (Score) -> Void
  private let onFailure: @MainActor (any Error) -> Void
  private let refreshOnAssetsLoaded: Bool

  private var revisionTask: Task<Void, Never>?
  private var assetsLoadedTask: Task<Void, Never>?
  private var inFlight: (task: Task<Void, Never>, snapshot: Snapshot)?
  private var cached: (snapshot: Snapshot, score: Score)?

  // - `willScore`: fires on a cache miss, before the pass spawns.
  // - `onFailure`: fires only on a non-cancellation `score` error.
  // - `refreshOnAssetsLoaded`: opt in when `score` reads
  //   `contextualEmbedding.assetsLoaded` and would return `.uncacheable` while
  //   the model is still downloading. The coordinator awaits the one-shot
  //   latch and kicks one refresh; saved-only surfaces leave it `false` and
  //   incur zero observation overhead.
  init(
    makeSnapshot: @escaping @MainActor () -> Snapshot?,
    willScore: @escaping @MainActor () -> Void = {},
    score: @escaping @MainActor () async throws -> ScoreResult,
    apply: @escaping @MainActor (Score) -> Void,
    onFailure: @escaping @MainActor (any Error) -> Void = { _ in },
    refreshOnAssetsLoaded: Bool = false
  ) {
    self.makeSnapshot = makeSnapshot
    self.willScore = willScore
    self.score = score
    self.apply = apply
    self.onFailure = onFailure
    self.refreshOnAssetsLoaded = refreshOnAssetsLoaded
  }

  // Idempotent. Builds the stream synchronously so a revision emitted before
  // the consuming task is scheduled is queued, not dropped.
  func startObservingScoringRevision() {
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
    let assetsLoaded = contextualEmbedding.assetsLoaded
    assetsLoadedTask = Task(priority: taskPriority(.utility)) { [weak self] in
      do {
        try await assetsLoaded.wait()
      } catch {
        return
      }
      guard let self, !Task.isCancelled else { return }
      refresh()
    }
  }

  // Gated on snapshot: skips when the snapshot is already cached or covered
  // by an in-flight pass. Since `Snapshot` must embed every input read by
  // `score`, an identical-snapshot restart is always wasted work.
  func refresh() {
    guard let snapshot = makeSnapshot() else { return }
    if let cached, cached.snapshot == snapshot {
      apply(cached.score)
      return
    }
    guard inFlight?.snapshot != snapshot else { return }
    willScore()
    inFlight?.task.cancel()
    let task = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }
      await runPass(for: snapshot)
    }
    inFlight = (task, snapshot)
  }

  private func runPass(for snapshot: Snapshot) async {
    // Only clear when no newer pass has taken over `inFlight`; a later
    // refresh() may have replaced it with a different snapshot.
    defer {
      if inFlight?.snapshot == snapshot { inFlight = nil }
    }
    do {
      let result = try await score()
      guard !Task.isCancelled else { return }
      // Stale-drop: inputs moved on while the pass was in flight.
      guard makeSnapshot() == snapshot else { return }
      switch result {
      case .cacheable(let score):
        cached = (snapshot, score)
        apply(score)
      case .uncacheable(let score):
        apply(score)
      }
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
    assetsLoadedTask?.cancel()
    assetsLoadedTask = nil
    inFlight?.task.cancel()
    inFlight = nil
  }
}
