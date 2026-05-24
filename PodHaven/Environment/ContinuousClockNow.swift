// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  var continuousClockNow: Factory<@Sendable () -> ContinuousClock.Instant> {
    Factory(self) { { ContinuousClock.now } }.cached
  }
}
