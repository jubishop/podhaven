// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

// Shared lifecycle + error-handling surface for podcast/episode detail
// view models. `runTask` wraps a user-action body in the canonical
// log-then-alert-when-remarkable shape used at every detail callsite, so
// conformers only write the work itself. `appear()` is provided as a
// default that simply funnels `performAppear()` through `runTask`.
// `clearObservationTask()` and `logStateTransition(to:)` give both VMs a
// shared observation-task and state-transition surface so each VM only
// keeps the parts that genuinely differ (e.g. the podcast side's
// `refreshEpisodeList` hook in its own `transition(to:)`).
@MainActor protocol DetailViewModel: AnyObject {
  associatedtype State: Sendable & Stringable

  var state: State { get }
  var observationTask: Task<Void, Never>? { get set }

  func performAppear() async throws
}

extension DetailViewModel {
  private var alert: Alert { Container.shared.alert() }

  nonisolated private static var log: Logger {
    Log.as(LogSubsystem.ViewProtocols.detailViewModel)
  }

  func appear() {
    runTask("appear") {
      try await self.performAppear()
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

  func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  func logStateTransition(to newState: State) {
    Self.log.debug("transitioning state \(state.toString) → \(newState.toString)")
  }
}
