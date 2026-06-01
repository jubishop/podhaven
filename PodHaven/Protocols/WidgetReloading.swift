// Copyright Justin Bishop, 2026

import WidgetKit

protocol WidgetReloading: Sendable {
  func placedWidgetKinds(
    _ completion: @escaping @Sendable (Result<Set<String>, any Error>) -> Void
  )
  func reloadTimelines(ofKind kind: String)
}

// WidgetCenter.shared is a process-wide singleton safe to use from any thread,
// but WidgetCenter doesn't declare Sendable conformance. This wrapper provides
// the Sendable conformance the protocol requires.
struct SystemWidgetCenter: WidgetReloading {
  func placedWidgetKinds(
    _ completion: @escaping @Sendable (Result<Set<String>, any Error>) -> Void
  ) {
    WidgetCenter.shared.getCurrentConfigurations { result in
      completion(result.map { configurations in Set(configurations.map(\.kind)) })
    }
  }

  func reloadTimelines(ofKind kind: String) {
    WidgetCenter.shared.reloadTimelines(ofKind: kind)
  }
}
