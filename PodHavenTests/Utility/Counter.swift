// Copyright Justin Bishop, 2025

import Foundation

final actor Counter: Sendable {
  private(set) var maxValue: Int = 0
  private(set) var minValue: Int = 0
  private(set) var value: Int = 0
  func callAsFunction(_ value: Int) {
    self.value = value
    minValue = min(minValue, value)
    maxValue = max(maxValue, value)
  }
  func increment() {
    value += 1
    maxValue = max(maxValue, value)
  }
  func decrement() {
    value -= 1
    minValue = min(minValue, value)
  }
}
