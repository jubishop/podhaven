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
  // clears the storage and clobbers the inner schedule's entry — the inner
  // task's Task reference still fires, but cancel() can no longer reach it.
  @Test("a recursive schedule survives the outer task's defer")
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
    let pendingAfterOuterFires = fakeSleeper.pendingCount()
    for _ in 0..<10 { await Task.yield() }

    #expect(aFired() == true)

    // Wait for the inner's sleep to register before probing state; otherwise
    // the next advance fires before the inner task parks on the sleeper.
    try await fakeSleeper.waitForSleepRequests(count: pendingAfterOuterFires + 1)

    // cancel() must reach the inner task. Under the bug, state.task was
    // cleared by outer's defer and cancel() would return false.
    #expect(debounce.cancel() == true)

    await fakeSleeper.advanceTime(by: .milliseconds(500))
    for _ in 0..<10 { await Task.yield() }

    #expect(bFired() == false)
  }

  // Without storing the task in the same critical section as the gen bump, a
  // zero-duration body can complete and run its defer before the handle is
  // published — leaving a completed task lodged in `state.task`.
  @Test("a zero-duration debounce reports no in-flight work after the action completes")
  func zeroDurationClearsInFlightAfterAction() async throws {
    let debounce = Debounce(duration: .zero)
    let fired = ThreadSafe<Bool>(false)

    debounce { fired(true) }

    try await Wait.until(
      { fired() == true },
      { "Expected the zero-duration action to fire." }
    )
    for _ in 0..<10 { await Task.yield() }

    #expect(debounce.cancel() == false)
  }
}
