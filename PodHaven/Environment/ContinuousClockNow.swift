// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  // Monotonic clock seam. Used by the FileLogHandler rate limiter so its
  // bucket math can be advanced deterministically in tests; production code
  // returns the live `ContinuousClock.now`. Wall-clock timestamps for log
  // entries themselves stay on `Date()` because log readers care about
  // wall-clock — only the rate limiter needs monotonicity.
  var continuousClockNow: Factory<@Sendable () -> ContinuousClock.Instant> {
    Factory(self) { { ContinuousClock.now } }.scope(.cached)
  }
}
