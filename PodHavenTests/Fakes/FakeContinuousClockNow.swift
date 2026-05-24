// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

extension Container {
  var fakeContinuousClockNow: Factory<FakeContinuousClockNow> {
    Factory(self) { FakeContinuousClockNow() }.scope(.cached)
  }
}

final class FakeContinuousClockNow: Sendable {
  private let storage: ThreadSafe<ContinuousClock.Instant>

  init(_ initial: ContinuousClock.Instant = ContinuousClock.now) {
    storage = ThreadSafe(initial)
  }

  func now() -> ContinuousClock.Instant {
    storage()
  }

  func advance(by duration: Duration) {
    storage { instant in
      instant += duration
      return instant
    }
  }
}
