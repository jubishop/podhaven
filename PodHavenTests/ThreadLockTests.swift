// Copyright Justin Bishop, 2026

import Semaphore
import Testing

@testable import PodHaven

@Suite("of ThreadLock")
struct ThreadLockTests {
  @Test("waitForClaim throws without ownership when the caller is already cancelled")
  func cancelledWaiterDoesNotClaim() async {
    let lock = ThreadLock()
    let start = AsyncSemaphore(value: 0)
    let waiter = Task {
      await start.wait()
      do {
        try await lock.waitForClaim()
        lock.release()
        return false
      } catch is CancellationError {
        return true
      } catch {
        Issue.record("Unexpected lock error: \(error)")
        return false
      }
    }

    waiter.cancel()
    start.signal()

    #expect(await waiter.value)
    #expect(!lock.isClaimed)
  }
}
