// Copyright Justin Bishop, 2025

import Foundation
import Semaphore

final actor Counter: Sendable {
  private(set) var maxValue: Int = 0
  private(set) var minValue: Int = 0
  private(set) var value: Int = 0

  var reachedExpected: Bool { value == expected }

  private let expected: Int
  private let semaphore = AsyncSemaphore(value: 0)

  init(expected: Int = 0) {
    self.expected = expected
  }

  func callAsFunction(_ value: Int) {
    self.value = value
    minValue = min(minValue, value)
    maxValue = max(maxValue, value)
  }

  func waitForExpected() async {
    for _ in 0..<expected {
      await semaphore.wait()
    }
  }

  func increment() {
    value += 1
    maxValue = max(maxValue, value)
    semaphore.signal()
  }

  func decrement() {
    value -= 1
    minValue = min(minValue, value)
  }
}
