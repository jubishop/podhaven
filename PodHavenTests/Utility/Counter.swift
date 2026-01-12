// Copyright Justin Bishop, 2025

import Foundation
import Semaphore

actor Counter: Sendable {
  private(set) var maxValue: Int
  private(set) var minValue: Int
  private(set) var value: Int

  func callAsFunction(_ newValue: Int) {
    set(to: newValue)
  }

  init(initialValue: Int = 0) {
    value = initialValue
    minValue = initialValue
    maxValue = initialValue
  }

  func wait(for expected: Int) async throws {
    try await Wait.until(
      { await self.value == expected },
      { "Counter value is \(await self.value), expected \(expected)" }
    )
  }

  func increment() {
    set(to: value + 1)
  }

  func decrement() {
    set(to: value - 1)
  }

  private func set(to newValue: Int) {
    value = newValue
    maxValue = max(maxValue, value)
    minValue = min(minValue, value)
  }
}
