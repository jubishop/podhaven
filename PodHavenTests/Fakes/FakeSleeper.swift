// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

actor FakeSleeper: Sleepable {
  private struct SleepRequest {
    let id: UUID
    let duration: Duration
    let wakeTime: Duration
    let continuation: CheckedContinuation<Void, Error>
  }

  private var sleepRequests: [SleepRequest] = []
  private var currentTime: Duration = .zero

  // Exposed outside the actor so waitForSleepRequests can poll without
  // competing for actor access — this fixes priority inversion where a
  // higher-priority polling loop starves a lower-priority task trying to
  // register its sleep request on the same actor.
  let pendingCount = ThreadSafe<Int>(0)
  let pendingDurations = ThreadSafe<[Duration]>([])

  // When set, a cancelled sleep throws CancellationError like Task.sleep;
  // otherwise it stays pending until time advances past it.
  let throwsOnCancellation = ThreadSafe(false)

  func sleep(for duration: Duration) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        guard !(throwsOnCancellation() && Task.isCancelled) else {
          continuation.resume(throwing: CancellationError())
          return
        }
        let wakeTime = currentTime + duration
        let request = SleepRequest(
          id: id,
          duration: duration,
          wakeTime: wakeTime,
          continuation: continuation
        )
        let insertionIndex = sleepRequests.firstIndex { $0.wakeTime > wakeTime }
        if let insertionIndex {
          sleepRequests.insert(request, at: insertionIndex)
        } else {
          sleepRequests.append(request)
        }
        pendingCount(sleepRequests.count)
        pendingDurations { $0.append(duration) }
      }
    } onCancel: {
      guard throwsOnCancellation() else { return }
      Task { await self.cancelSleep(id) }
    }
  }

  func advanceTime(by duration: Duration) {
    currentTime += duration
    while let first = sleepRequests.first, first.wakeTime <= currentTime {
      sleepRequests.removeFirst()
      removePendingDuration(first.duration)
      first.continuation.resume(returning: ())
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

  private func cancelSleep(_ id: UUID) {
    guard let index = sleepRequests.firstIndex(where: { $0.id == id }) else { return }
    let request = sleepRequests.remove(at: index)
    removePendingDuration(request.duration)
    pendingCount(sleepRequests.count)
    request.continuation.resume(throwing: CancellationError())
  }

  private func removePendingDuration(_ duration: Duration) {
    pendingDurations { durations in
      guard let index = durations.firstIndex(of: duration) else { return }
      durations.remove(at: index)
    }
  }
}
