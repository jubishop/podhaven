// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor FakeSleeper: Sleepable {
  private var sleepRequests:
    [(wakeTime: Duration, continuation: CheckedContinuation<Void, Error>)] = []
  private var currentTime: Duration = .zero

  var _skipAllSleeps = false
  func skipAllSleeps() {
    _skipAllSleeps = true
  }

  func sleep(for duration: Duration) async throws {
    if _skipAllSleeps { return }

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let wakeTime = currentTime + duration
      let request = (wakeTime: wakeTime, continuation: continuation)
      let insertionIndex = sleepRequests.firstIndex { $0.wakeTime > wakeTime }
      if let insertionIndex {
        sleepRequests.insert(request, at: insertionIndex)
      } else {
        sleepRequests.append(request)
      }
    }
  }

  func advanceTime(by duration: Duration) {
    Assert.precondition(
      !_skipAllSleeps,
      "Cannot advance time while skipping all sleeps"
    )

    currentTime += duration
    while let first = sleepRequests.first, first.wakeTime <= currentTime {
      first.continuation.resume(returning: ())
      sleepRequests.removeFirst()
    }
  }

  func waitForSleepRequests(count: Int) async throws {
    Assert.precondition(
      !_skipAllSleeps,
      "Cannot wait for sleep requests while skipping all sleeps"
    )

    try await Wait.until(
      { await self.sleepRequests.count >= count },
      { "Expected \(count) sleep requests, but got \(await self.sleepRequests.count)" }
    )
  }
}
