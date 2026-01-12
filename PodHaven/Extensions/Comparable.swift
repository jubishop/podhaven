// Copyright Justin Bishop, 2025

import Foundation

extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    Swift.max(limits.lowerBound, Swift.min(self, limits.upperBound))
  }
}
