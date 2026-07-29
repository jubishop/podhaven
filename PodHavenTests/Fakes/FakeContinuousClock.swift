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
  private let beforeNextNow = ThreadSafe<(@Sendable () -> Void)?>(nil)

  var now: ContinuousClock.Instant {
    let operation = beforeNextNow { pending in
      let operation = pending
      pending = nil
      return operation
    }
    operation?()

    return mode { current in
      switch current {
      case .passthrough:
        return ContinuousClock.now
      case .manual(let instant):
        return instant
      }
    }
  }

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

  func runBeforeNextNow(_ operation: @escaping @Sendable () -> Void) {
    let registered = beforeNextNow { pending in
      guard pending == nil else { return false }
      pending = operation
      return true
    }
    Assert.precondition(registered, "A clock operation is already pending")
  }
}
