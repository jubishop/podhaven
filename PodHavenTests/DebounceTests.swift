// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Debounce tests", .container)
struct DebounceTests {
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper { sleeper as! FakeSleeper }

  // Without generation tracking on `state.task`, the outer task's defer
  // unconditionally nils the storage, clobbering the inner schedule's task.
  @Test(
    "a recursive callAsFunction from within the action body survives the outer task's completion defer"
  )
  func recursiveScheduleSurvivesOuterTaskCompletionDefer() async throws {
    let debounce = Debounce(duration: .milliseconds(500))
    let aFired = ThreadSafe<Bool>(false)
    let bFired = ThreadSafe<Bool>(false)

    debounce {
      aFired(true)
      debounce { bFired(true) }
    }

    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .milliseconds(500))
    for _ in 0..<10 { await Task.yield() }

    #expect(aFired() == true)
    #expect(debounce.hasInFlightTask == true)
    #expect(bFired() == false)

    await fakeSleeper.advanceTime(by: .milliseconds(500))
    for _ in 0..<10 { await Task.yield() }

    #expect(bFired() == true)
    #expect(debounce.hasInFlightTask == false)
  }
}
