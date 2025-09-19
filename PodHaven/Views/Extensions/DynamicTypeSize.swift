// Copyright Justin Bishop, 2025

import SwiftUI

extension DynamicTypeSize {
  func clamped(
    minimum: DynamicTypeSize?,
    maximum: DynamicTypeSize?
  ) -> DynamicTypeSize {
    var result = self

    if let minimum, result < minimum {
      result = minimum
    }

    if let maximum, result > maximum {
      result = maximum
    }

    return result
  }
}
