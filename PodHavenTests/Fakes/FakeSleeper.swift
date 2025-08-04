// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor FakeSleeper: Sleepable {
  private var sleepRequests:
    [(wakeTime: Duration, continuation: CheckedContinuation<Void, Error>)] = []
  private var currentTime: Duration = .zero

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
    }
  }

  func advanceTime(by duration: Duration) {
    currentTime += duration

    while let first = sleepRequests.first, first.wakeTime <= currentTime {
      first.continuation.resume(returning: ())
      sleepRequests.removeFirst()
    }
  }

  func waitForRegistrations(count: Int) async throws {
    try await Wait.until(
      { await self.sleepRequests.count >= count },
      { "Expected \(count) sleep requests, but got \(await self.sleepRequests.count)" }
    )
  }
}
