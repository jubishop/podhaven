// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor FakeSleeper: Sleepable {
  private var sleepRequests:
    [(duration: Duration, wakeTime: Duration, continuation: CheckedContinuation<Void, Error>)] = []
  private var currentTime: Duration = .zero

  // Exposed outside the actor so waitForSleepRequests can poll without
  // competing for actor access — this fixes priority inversion where a
  // higher-priority polling loop starves a lower-priority task trying to
  // register its sleep request on the same actor.
  let pendingCount = ThreadSafe<Int>(0)
  let pendingDurations = ThreadSafe<[Duration]>([])

  func sleep(for duration: Duration) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      let wakeTime = currentTime + duration
      let request = (duration: duration, wakeTime: wakeTime, continuation: continuation)
      let insertionIndex = sleepRequests.firstIndex { $0.wakeTime > wakeTime }
      if let insertionIndex {
        sleepRequests.insert(request, at: insertionIndex)
      } else {
        sleepRequests.append(request)
      }
      pendingCount(sleepRequests.count)
      pendingDurations { $0.append(duration) }
    }
  }

  func advanceTime(by duration: Duration) {
    currentTime += duration
    while let first = sleepRequests.first, first.wakeTime <= currentTime {
      first.continuation.resume(returning: ())
      sleepRequests.removeFirst()
      pendingDurations { durations in
        guard let index = durations.firstIndex(of: first.duration) else { return }
        durations.remove(at: index)
      }
    }
    pendingCount(sleepRequests.count)
  }

  nonisolated func waitForSleepRequests(count: Int) async throws {
    try await Wait.until(
      { self.pendingCount() >= count },
      { "Expected \(count) sleep requests, but got \(self.pendingCount())" }
    )
  }

  nonisolated func waitForSleepRequests(for duration: Duration, count: Int = 1) async throws {
    try await Wait.until(
      { self.pendingDurations().count { $0 == duration } >= count },
      {
        "Expected \(count) sleep requests for \(duration), got \(self.pendingDurations())"
      }
    )
  }
}
