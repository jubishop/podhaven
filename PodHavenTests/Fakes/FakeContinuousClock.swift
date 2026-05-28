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
  private enum Mode: Sendable {
    case passthrough
    case manual(ContinuousClock.Instant)
  }

  private let mode = ThreadSafe<Mode>(.passthrough)

  var now: ContinuousClock.Instant {
    mode { current in
      switch current {
      case .passthrough:
        return ContinuousClock.now
      case .manual(let instant):
        return instant
      }
    }
  }

  // Holds time still for rate-limiter tests that flood one site without refills.
  func freeze(at instant: ContinuousClock.Instant = .now) {
    mode { current in
      current = .manual(instant)
    }
  }

  func advance(by duration: Duration) {
    mode { current in
      let base: ContinuousClock.Instant
      switch current {
      case .passthrough:
        base = ContinuousClock.now
      case .manual(let instant):
        base = instant
      }
      current = .manual(base.advanced(by: duration))
    }
  }
}
