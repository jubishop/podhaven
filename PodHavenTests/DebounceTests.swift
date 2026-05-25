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

    // Outer task parks on its 500ms sleep.
    try await fakeSleeper.waitForSleepRequests(count: 1)

    // Fire the outer's sleep. The continuation resumes asynchronously, so the
    // outer body may not have run yet when this returns.
    await fakeSleeper.advanceTime(by: .milliseconds(500))

    // Synchronize on aFired before probing further state — guarantees the
    // outer body finished `aFired(true)` and ran `debounce { bFired(true) }`
    // without depending on a fixed yield budget (which can starve under
    // parallel-suite load).
    try await Wait.until(
      { aFired() == true },
      { "Expected the outer action to set aFired." }
    )

    // The outer body's recursive schedule queued an inner task; wait for it
    // to register its 500ms sleep before cancelling.
    try await fakeSleeper.waitForSleepRequests(count: 1)

    // cancel() must reach the inner task. Under the bug, state.task was
    // cleared by outer's defer and cancel() would return false.
    #expect(debounce.cancel() == true)

    // Fire the (now-cancelled) inner sleep so the inner task gets to evaluate
    // its `guard !Task.isCancelled` early-out.
    await fakeSleeper.advanceTime(by: .milliseconds(500))

    // Under the fix the cancelled inner task returns through its guard
    // without running action(); bFired stays false. Under the bug the inner
    // task is unreachable from cancel() and its action fires, flipping
    // bFired. Bound the wait so the bug has a chance to manifest before we
    // declare the test green.
    let bRan: Bool
    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(20),
        { bFired() == true },
        { "" }
      )
      bRan = true
    } catch TestError.waitUntilFailure {
      bRan = false
    }
    #expect(bRan == false, "Inner action should not have run after cancel().")
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
