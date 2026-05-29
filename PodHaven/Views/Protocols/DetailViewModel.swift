// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

// Shared lifecycle + error-handling for podcast/episode detail view models.
//
// Invariants:
// - `appear()` dedupes an overlapping in-flight `appearTask`; after the first
//   pass completes, a later `onAppear` cancels any prior `appearTask` and runs
//   `performAppear()` again. It does not cancel `observationTask`.
// - `performAppear()` gates async steps with `try Task.checkCancellation()`; a
//   superseded or disappeared pass is cancelled, so each step bails on resume.
// - `disappear()` sets `isOnScreen = false` and cancels appear-scoped work;
//   `runTask` children are not cancelled unless the conformer guards them.
// - `transition(to:)` may update `state` off-screen; projections and long-lived
//   work require `isOnScreen` in each detail view model.
@MainActor protocol DetailViewModel: AnyObject {
  associatedtype State: Sendable & Stringable

  var alert: Alert { get }
  var state: State { get }
  var isOnScreen: Bool { get set }
  var appearTask: Task<Void, Never>? { get set }
  var observationTask: Task<Void, Never>? { get set }

  func performAppear() async throws
  func cancelDetailPassAuxiliaryWork()
}

extension DetailViewModel {
  nonisolated private static var log: Logger {
    Log.as(LogSubsystem.ViewProtocols.detailViewModel)
  }

  func appear() {
    if isOnScreen, let appearTask, !appearTask.isCancelled {
      return
    }
    isOnScreen = true
    appearTask?.cancel()
    cancelDetailPassAuxiliaryWork()
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
  }

  func disappear() {
    isOnScreen = false
    cancelDetailPassAuxiliaryWork()
    cancelAppearScopedAsyncWork()
  }

  func cancelDetailPassAuxiliaryWork() {}

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

  func cancelAppearScopedAsyncWork() {
    appearTask?.cancel()
    appearTask = nil
    observationTask?.cancel()
    observationTask = nil
  }

}
