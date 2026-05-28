// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  // Monotonic clock seam for production timing and test control via
  // `fakeContinuousClock` in the `.test` container context.
  var continuousClockNow: Factory<@Sendable () -> ContinuousClock.Instant> {
    Factory(self) { { ContinuousClock.now } }.scope(.cached)
  }
}
