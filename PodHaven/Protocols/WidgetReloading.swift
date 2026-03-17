// Copyright Justin Bishop, 2026

import WidgetKit

protocol WidgetReloading: Sendable {
  func getCurrentConfigurations(
    _ completion: @escaping @Sendable (Result<[WidgetKit.WidgetInfo], any Error>) -> Void
  )
  func reloadTimelines(ofKind kind: String)
}

// WidgetCenter.shared is a process-wide singleton safe to use from any thread,
// but WidgetCenter doesn't declare Sendable conformance. This wrapper provides
// the Sendable conformance the protocol requires.
struct SystemWidgetCenter: WidgetReloading {
  func getCurrentConfigurations(
    _ completion: @escaping @Sendable (Result<[WidgetKit.WidgetInfo], any Error>) -> Void
  ) {
    WidgetCenter.shared.getCurrentConfigurations(completion)
  }

  func reloadTimelines(ofKind kind: String) {
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }
}
