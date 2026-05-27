// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeContinuousClock: Factory<FakeContinuousClock> {
    Factory(self) { FakeContinuousClock() }.scope(.cached)
  }
}

final class FakeContinuousClock: Sendable {
  private let current: ThreadSafe<ContinuousClock.Instant>

  init(start: ContinuousClock.Instant = .now) {
    self.current = ThreadSafe(start)
  }

  var now: ContinuousClock.Instant {
    current()
  }

  func advance(by duration: Duration) {
    current { $0 = $0.advanced(by: duration) }
  }
}
