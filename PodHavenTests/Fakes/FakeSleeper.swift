// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor FakeSleeper: Sleepable {
  private var sleepRequests:
    [(wakeTime: Duration, continuation: CheckedContinuation<Void, Error>)] = []
  private var currentTime: Duration = .zero

  // Exposed outside the actor so waitForSleepRequests can poll without
  // competing for actor access — this fixes priority inversion where a
  // higher-priority polling loop starves a lower-priority task trying to
  // register its sleep request on the same actor.
  let pendingCount = ThreadSafe<Int>(0)

  func sleep(for duration: Duration) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let wakeTime = currentTime + duration
      let request = (wakeTime: wakeTime, continuation: continuation)
      let insertionIndex = sleepRequests.firstIndex { $0.wakeTime > wakeTime }
      if let insertionIndex {
        sleepRequests.insert(request, at: insertionIndex)
      } else {
        sleepRequests.append(request)
      }
      pendingCount(sleepRequests.count)
    }
  }

  func advanceTime(by duration: Duration) {
    currentTime += duration
    while let first = sleepRequests.first, first.wakeTime <= currentTime {
      first.continuation.resume(returning: ())
      sleepRequests.removeFirst()
    }
    pendingCount(sleepRequests.count)
  }

  nonisolated func waitForSleepRequests(count: Int) async throws {
    try await Wait.until(
      { self.pendingCount() >= count },
      { "Expected \(count) sleep requests, but got \(self.pendingCount())" }
    )
  }
}
