// Copyright Justin Bishop, 2026

import Logging

// Shared lifecycle + error-handling surface for podcast/episode detail
// view models. `runTask` wraps a user-action body in the canonical
// log-then-alert-when-remarkable shape used at every detail callsite, so
// conformers only write the work itself. `appear()` is provided as a
// default that simply funnels `performAppear()` through `runTask`.
@MainActor protocol DetailViewModel: AnyObject {
  nonisolated static var log: Logger { get }
  var alert: Alert { get }

  func performAppear() async throws
}

extension DetailViewModel {
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
