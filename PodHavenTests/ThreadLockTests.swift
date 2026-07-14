// Copyright Justin Bishop, 2026

import Semaphore
import Testing

@testable import PodHaven

@Suite("of ThreadLock")
struct ThreadLockTests {
  @Test("waitForClaim returns with ownership when the caller is cancelled")
  func cancelledWaiterReturnsWithOwnership() async {
    let lock = ThreadLock()
    let start = AsyncSemaphore(value: 0)
    let waiter = Task {
      await start.wait()
      await lock.waitForClaim()
      let ownsClaim = lock.isClaimed
      lock.release()
      return ownsClaim
    }

    waiter.cancel()
    start.signal()

    #expect(await waiter.value)
  }
}
