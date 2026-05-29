// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

// Shared lifecycle plumbing composed by the podcast/episode detail view models.
//
// Owns the on-screen flag plus the appear/observation task handles so a view
// model is side-effect-free at `init`; SwiftUI re-evaluates detail destinations,
// and only the appeared model runs `performAppear`.
//
// Invariants:
// - `appear(performAppear:)` dedupes an overlapping in-flight `appearTask`,
//   returning `false` when it reuses one and `true` when it starts a fresh
//   pass, so the caller can reset its own auxiliary work. It does not cancel
//   `observationTask`.
// - `startObservation(_:)` dedupes a live `observationTask`, returning `false`
//   when it reuses one, and clears the handle on any natural (non-cancelled)
//   exit of the supplied body.
// - `performAppear` gates async steps with `try Task.checkCancellation()`, so a
//   superseded or disappeared pass bails on resume.
// - `disappear()` clears `isOnScreen` and cancels both the appear and
//   observation tasks.
@MainActor final class DetailLifecycle {
  @DynamicInjected(\.alert) private var alert

  private(set) var isOnScreen = false
  private(set) var observationTask: Task<Void, Never>?
  private var appearTask: Task<Void, Never>?

  nonisolated private static var log: Logger {
    Log.as(LogSubsystem.ViewProtocols.detailViewModel)
  }

  func appear(performAppear: @escaping () async throws -> Void) -> Bool {
    if isOnScreen, let appearTask, !appearTask.isCancelled {
      return false
    }
    isOnScreen = true
    appearTask?.cancel()
    appearTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if !Task.isCancelled {
          appearTask = nil
        }
      }
      do {
        try await performAppear()
      } catch {
        Self.log.caughtError("appear: failed", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
    return true
  }

  func disappear() {
    isOnScreen = false
    appearTask?.cancel()
    appearTask = nil
    observationTask?.cancel()
    observationTask = nil
  }

  // Runs `observe` as the observation task unless one is already active,
  // returning true when it created a fresh task and false when it reused a
  // live one. Clears the handle on any natural (non-cancelled) exit; skips
  // clearing when cancelled, since disappear() or a re-binding start already
  // cleared/replaced it and stomping would kill a newer task.
  @discardableResult
  func startObservation(_ observe: @escaping () async -> Void) -> Bool {
    if let observationTask, !observationTask.isCancelled {
      return false
    }
    observationTask?.cancel()
    observationTask = Task { [weak self] in
      guard let self else { return }
      defer {
        if !Task.isCancelled {
          observationTask = nil
        }
      }
      await observe()
    }
    return true
  }

  func runTask(
    _ context: String,
    _ body: @escaping () async throws -> Void
  ) {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await body()
      } catch {
        Self.log.caughtError("\(context): failed", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
