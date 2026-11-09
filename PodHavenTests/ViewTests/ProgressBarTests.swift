// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of ProgressBar position tests", .container)
struct ProgressBarTests {
  @Test(
    "a value's position is its share of the range, clamped to the range",
    arguments: [(0.0, 0.0), (25.0, 0.25), (100.0, 1.0), (150.0, 1.0), (-10.0, 0.0)]
  )
  func positionWithinRange(value: Double, expected: Double) {
    #expect(ProgressBar.fraction(of: value, in: 0...100) == expected)
  }

  // Regression: markers divided by the range's width, so an unknown (zero)
  // duration placed them at a non-finite position.
  @Test("a zero-width range places every value at the start", arguments: [0.0, 30.0])
  func zeroWidthRange(value: Double) {
    #expect(ProgressBar.fraction(of: value, in: 0...0) == 0)
  }
}
