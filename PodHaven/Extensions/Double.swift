// Copyright Justin Bishop, 2025

import Foundation

extension Double {
  func formatted(decimalPlaces: Int = 1) -> String {
    formatted(.number.precision(.fractionLength(decimalPlaces...decimalPlaces)))
  }
}
