// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

struct DetailAuxiliaryTask: Sendable {
  let id: UUID
  let task: Task<Void, Never>
}

// Shared lifecycle + error-handling for podcast/episode detail view models.
//
// Invariants:
// - `appear()` only dedupes an overlapping in-flight `appearTask`; after the
//   first pass completes, a later `onAppear` bumps `appearGeneration` and runs
//   `performAppear()` again. It does not cancel `observationTask`.
// - `performAppear()` must gate async steps with `isCurrentAppearPass(_:)`;
//   idempotency for observation, feed fetch, and list projection is per-step.
// - `disappear()` sets `isOnScreen = false` and cancels appear-scoped work;
//   `runTask` children are not cancelled unless the conformer guards them.
// - `transition(to:)` may update `state` off-screen; projections and long-lived
//   work require `isOnScreen` in each detail view model.
@MainActor protocol DetailViewModel: AnyObject {
  associatedtype State: Sendable & Stringable

  var alert: Alert { get }
  var state: State { get }
  var isOnScreen: Bool { get set }
  var appearGeneration: Int { get set }
  var appearTask: Task<Void, Never>? { get set }
  var observationTask: Task<Void, Never>? { get set }
  var auxiliaryTasks: [DetailAuxiliaryTask] { get set }

  func performAppear() async throws
  func cancelDetailPassAuxiliaryWork()
}

extension DetailViewModel {
  nonisolated private static var log: Logger {
    Log.as(LogSubsystem.ViewProtocols.detailViewModel)
  }

  func isCurrentAppearPass(_ generation: Int) -> Bool {
    isOnScreen && appearGeneration == generation
  }

  func appear() {
    if isOnScreen, let appearTask, !appearTask.isCancelled {
      return
    }
    isOnScreen = true
    appearGeneration += 1
    appearTask?.cancel()
    for entry in auxiliaryTasks { entry.task.cancel() }
    auxiliaryTasks.removeAll()
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
    for entry in auxiliaryTasks { entry.task.cancel() }
    auxiliaryTasks.removeAll()
  }

  func track(_ task: Task<Void, Never>) {
    let entry = DetailAuxiliaryTask(id: UUID(), task: task)
    auxiliaryTasks.append(entry)
    Task { [weak self] in
      await task.value
      guard let self else { return }
      auxiliaryTasks.removeAll { $0.id == entry.id }
    }
  }

}
