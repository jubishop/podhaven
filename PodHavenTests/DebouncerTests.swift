// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Debouncer tests", .container)
@MainActor struct DebouncerTests {
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  @Test("cancelPending stops the pending fire but keeps the current value")
  func cancelPendingKeepsValue() async throws {
    let fired = ThreadSafe<Bool>(false)
    let debouncer = StringDebouncer(debounceDuration: .milliseconds(500)) { _ in fired(true) }

    debouncer.currentValue = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)

    debouncer.cancelPending()
    await fakeSleeper.advanceTime(by: .milliseconds(500))

    #expect(await didFire(fired) == false, "cancelPending must stop the pending onChange")
    #expect(debouncer.currentValue == "growth", "cancelPending must keep the current value")
    #expect(debouncer.debouncedValue == "", "onChange never ran, so debouncedValue stays initial")
  }

  @Test("cancelPending then commitValue stops the pending fire and commits the value")
  func commitValueCommitsWithoutFiringOnChange() async throws {
    let fired = ThreadSafe<Bool>(false)
    let debouncer = StringDebouncer(debounceDuration: .milliseconds(500)) { _ in fired(true) }

    debouncer.currentValue = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)

    debouncer.cancelPending()
    debouncer.commitValue()
    await fakeSleeper.advanceTime(by: .milliseconds(500))

    #expect(await didFire(fired) == false, "committing must stop the pending onChange")
    #expect(debouncer.currentValue == "growth", "committing must keep the current value")
    #expect(debouncer.debouncedValue == "growth", "committing must update the debounced value")
  }

  @Test("reset stops the pending fire and clears the value")
  func resetClearsValue() async throws {
    let fired = ThreadSafe<Bool>(false)
    let debouncer = StringDebouncer(debounceDuration: .milliseconds(500)) { _ in fired(true) }

    debouncer.currentValue = "growth"
    try await fakeSleeper.waitForSleepRequests(count: 1)

    debouncer.reset()
    await fakeSleeper.advanceTime(by: .milliseconds(500))

    #expect(await didFire(fired) == false, "reset must stop the pending onChange")
    #expect(debouncer.currentValue == "", "reset must clear the current value")
  }

  // Bounded wait so a wrongly-firing action has a chance to flip the flag
  // before we assert it stayed false.
  private func didFire(_ fired: ThreadSafe<Bool>) async -> Bool {
    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(20),
        { fired() == true },
        { "" }
      )
      return true
    } catch {
      return false
    }
  }
}
