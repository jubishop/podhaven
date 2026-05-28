// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

// Shared lifecycle + error-handling for podcast/episode detail view models.
@MainActor protocol DetailViewModel: AnyObject {
  associatedtype State: Sendable & Stringable

  var state: State { get }
  var appearTask: Task<Void, Never>? { get set }
  var observationTask: Task<Void, Never>? { get set }
  var auxiliaryTasks: [Task<Void, Never>] { get set }

  func performAppear() async throws
}

extension DetailViewModel {
  private var alert: Alert { Container.shared.alert() }

  nonisolated private static var log: Logger {
    Log.as(LogSubsystem.ViewProtocols.detailViewModel)
  }

  func appear() {
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

  func cancelAppearScopedAsyncWork() {
    appearTask?.cancel()
    appearTask = nil
    observationTask?.cancel()
    observationTask = nil
    for task in auxiliaryTasks { task.cancel() }
    auxiliaryTasks.removeAll()
  }

  func track(_ task: Task<Void, Never>) {
    auxiliaryTasks.append(task)
  }

  func logStateTransition(to newState: State) {
    Self.log.debug("transitioning state \(state.toString) → \(newState.toString)")
  }
}
