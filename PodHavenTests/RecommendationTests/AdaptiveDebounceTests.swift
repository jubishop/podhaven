// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of AdaptiveDebounce tests", .container)
struct AdaptiveDebounceTests {
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.fakeContinuousClockNow) private var fakeClock

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  private func arm(_ debounce: AdaptiveDebounce) async throws -> ThreadSafe<Bool> {
    let pendingAtStart = fakeSleeper.pendingCount()
    let fired = ThreadSafe<Bool>(false)
    debounce { () async -> Void in
      fired(true)
    }
    try await fakeSleeper.waitForSleepRequests(count: pendingAtStart + 1)
    return fired
  }

  private func didFireAfter(_ duration: Duration, fired: ThreadSafe<Bool>) async -> Bool {
    await fakeSleeper.advanceTime(by: duration)
    // Poll for fire with a short wall-clock budget; the new schedule chain
    // has an extra await layer so a fixed yield count flakes under load.
    for _ in 0..<100 {
      if fired() { return true }
      await Task.yield()
    }
    return fired()
  }

  // Drives one full schedule → fire → record cycle so the window picks up a
  // pass of the given wall-clock duration (simulated via the fake clock).
  // Uses a local fired flag because passDurations.count stops growing once
  // the window is at capacity.
  private func seedPass(
    _ debounce: AdaptiveDebounce,
    duration: Duration
  ) async throws {
    let fakeClock = self.fakeClock
    let pendingAtStart = fakeSleeper.pendingCount()
    let actionFired = ThreadSafe<Bool>(false)
    debounce { () async -> Void in
      fakeClock.advance(by: duration)
      actionFired(true)
    }
    try await fakeSleeper.waitForSleepRequests(count: pendingAtStart + 1)
    await fakeSleeper.advanceTime(by: debounce.maximumDuration)
    try await Wait.until(
      { actionFired() },
      { "Seed pass action did not run" }
    )
  }

  @Test("an empty window debounces at the minimum floor")
  func emptyWindowFloorsToMinimum() async throws {
    let debounce = AdaptiveDebounce(
      name: "empty-window-floor",
      minimumDuration: .milliseconds(500),
      maximumDuration: .seconds(60)
    )
    let fired = try await arm(debounce)

    #expect(await didFireAfter(.milliseconds(499), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("a recorded pass sizes the next debounce to max × safety multiplier")
  func recordedPassResizesNextDebounce() async throws {
    let debounce = AdaptiveDebounce(
      name: "recorded-resize",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60),
      safetyMultiplier: 3.0
    )
    try await seedPass(debounce, duration: .milliseconds(500))
    let fired = try await arm(debounce)

    #expect(await didFireAfter(.milliseconds(1499), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("sub-floor recorded passes still clamp up to the minimum")
  func subFloorEntriesClampUpToFloor() async throws {
    let debounce = AdaptiveDebounce(
      name: "subfloor-clamp",
      minimumDuration: .milliseconds(500),
      maximumDuration: .seconds(60)
    )
    try await seedPass(debounce, duration: .milliseconds(50))
    let fired = try await arm(debounce)

    #expect(await didFireAfter(.milliseconds(499), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("a recorded pass that would exceed the cap clamps to the cap")
  func aboveCapEntriesClampDownToCap() async throws {
    let debounce = AdaptiveDebounce(
      name: "above-cap",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(2),
      safetyMultiplier: 2.0
    )
    try await seedPass(debounce, duration: .seconds(4))
    let fired = try await arm(debounce)

    #expect(await didFireAfter(.milliseconds(1999), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("a slow outlier ages out after `capacity` fast passes")
  func slowOutlierAgesOutAfterCapacityFastEntries() async throws {
    let debounce = AdaptiveDebounce(
      name: "outlier-aging",
      capacity: 3,
      minimumDuration: .milliseconds(200),
      maximumDuration: .seconds(60)
    )
    try await seedPass(debounce, duration: .seconds(2))
    for _ in 0..<debounce.capacity {
      try await seedPass(debounce, duration: .milliseconds(50))
    }
    let fired = try await arm(debounce)

    #expect(await didFireAfter(.milliseconds(199), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("a freshly-constructed AdaptiveDebounce reads the persisted window from a prior instance")
  func persistsAcrossInstancesWithSameName() async throws {
    let first = AdaptiveDebounce(
      name: "persisted",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60),
      safetyMultiplier: 2.0
    )
    try await seedPass(first, duration: .milliseconds(750))

    let second = AdaptiveDebounce(
      name: "persisted",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60),
      safetyMultiplier: 2.0
    )
    let fired = try await arm(second)

    #expect(await didFireAfter(.milliseconds(1499), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("instances with different names persist to independent windows")
  func differentNamesUseIndependentWindows() async throws {
    let a = AdaptiveDebounce(
      name: "isolated-a",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60),
      safetyMultiplier: 2.0
    )
    try await seedPass(a, duration: .seconds(1))

    let b = AdaptiveDebounce(
      name: "isolated-b",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60),
      safetyMultiplier: 2.0
    )
    let fired = try await arm(b)

    #expect(await didFireAfter(.milliseconds(99), fired: fired) == false)
    #expect(await didFireAfter(.milliseconds(2), fired: fired) == true)
  }

  @Test("cancel kills an in-flight action and hasInFlightTask flips back to false")
  func cancelStopsArmedActionAndClearsInFlight() async throws {
    let debounce = AdaptiveDebounce(
      name: "cancel-cleanup",
      minimumDuration: .seconds(1),
      maximumDuration: .seconds(60)
    )
    let fired = try await arm(debounce)
    #expect(debounce.hasInFlightTask == true)

    debounce.cancel()
    _ = await didFireAfter(.seconds(2), fired: fired)

    #expect(fired() == false)
    #expect(debounce.hasInFlightTask == false)
  }

  @Test("a Bool action returning true records its elapsed duration")
  func boolActionReturningTrueRecordsDuration() async throws {
    let fakeClock = self.fakeClock
    let debounce = AdaptiveDebounce(
      name: "bool-true",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60)
    )
    debounce { () async -> Bool in
      fakeClock.advance(by: .milliseconds(750))
      return true
    }
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(100))

    try await Wait.until(
      { debounce.passDurations == [.milliseconds(750)] },
      { "Expected Bool true action to record 750ms; got \(debounce.passDurations)" }
    )
  }

  @Test("a Bool action returning false does not record")
  func boolActionReturningFalseDoesNotRecord() async throws {
    let fakeClock = self.fakeClock
    let debounce = AdaptiveDebounce(
      name: "bool-false",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60)
    )
    debounce { () async -> Bool in
      fakeClock.advance(by: .milliseconds(750))
      return false
    }
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(100))

    try await Wait.until(
      { debounce.hasInFlightTask == false },
      { "Expected debounce task to clear after Bool false action" }
    )
    #expect(debounce.passDurations.isEmpty)
  }

  @Test("a Void action always records its elapsed duration")
  func voidActionAlwaysRecords() async throws {
    let fakeClock = self.fakeClock
    let debounce = AdaptiveDebounce(
      name: "void-records",
      minimumDuration: .milliseconds(100),
      maximumDuration: .seconds(60)
    )
    debounce { () async -> Void in
      fakeClock.advance(by: .milliseconds(400))
    }
    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(100))

    try await Wait.until(
      { debounce.passDurations == [.milliseconds(400)] },
      { "Expected Void action to record 400ms; got \(debounce.passDurations)" }
    )
  }
}
