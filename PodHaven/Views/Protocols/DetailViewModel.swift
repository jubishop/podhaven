// Copyright Justin Bishop, 2026

import FactoryKit
import Logging

// Shared lifecycle + error-handling surface for podcast/episode detail
// view models. `runTask` wraps a user-action body in the canonical
// log-then-alert-when-remarkable shape used at every detail callsite, so
// conformers only write the work itself. `appear()` is provided as a
// default that simply funnels `performAppear()` through `runTask`.
@MainActor protocol DetailViewModel: AnyObject {
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
}
