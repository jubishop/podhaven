// Copyright Justin Bishop, 2024

import Foundation

actor Counter: Sendable {
  private(set) var maxValue: Int = 0
  private(set) var minValue: Int = 0
  private(set) var value: Int = 0
  func increment() {
    value += 1
    maxValue = max(maxValue, value)
  }
  func decrement() {
    value -= 1
    minValue = min(minValue, value)
  }
}
