// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of AdaptiveDebounce tests", .container)
struct AdaptiveDebounceTests {
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  private func arm(_ debounce: AdaptiveDebounce) async throws -> ThreadSafe<Bool> {
    let fired = ThreadSafe<Bool>(false)
    debounce { fired(true) }
    try await fakeSleeper.waitForSleepRequests(count: 1)
    return fired
  }

  private func didFireAfter(_ duration: Duration, fired: ThreadSafe<Bool>) async -> Bool {
    await fakeSleeper.advanceTime(by: duration)
    for _ in 0..<10 { await Task.yield() }
    return fired()
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
    debounce.recordCompletedPass(.milliseconds(500))
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
    debounce.recordCompletedPass(.milliseconds(50))
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
    debounce.recordCompletedPass(.seconds(4))
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
    debounce.recordCompletedPass(.seconds(2))
    for _ in 0..<debounce.capacity {
      debounce.recordCompletedPass(.milliseconds(50))
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
    first.recordCompletedPass(.milliseconds(750))

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
    a.recordCompletedPass(.seconds(1))

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
}
