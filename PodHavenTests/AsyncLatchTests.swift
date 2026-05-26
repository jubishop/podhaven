// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AsyncLatch tests")
struct AsyncLatchTests {
  @Test("isOpen is false on a fresh latch")
  func freshLatchIsClosed() {
    let latch = AsyncLatch<Void>()
    #expect(!latch.isOpen)
    #expect(latch.openValue == nil)
  }

  @Test("open flips isOpen and exposes the value")
  func openStoresValue() {
    let latch = AsyncLatch<Int>()
    latch.open(42)
    #expect(latch.isOpen)
    #expect(latch.openValue == 42)
  }

  @Test("wait returns immediately on an already-open void latch")
  func waitReturnsImmediatelyWhenOpen() async throws {
    let latch = AsyncLatch<Void>()
    latch.open()
    try await latch.wait()
  }

  @Test("wait returns the stored value on an already-open valued latch")
  func waitReturnsValue() async throws {
    let latch = AsyncLatch<String>()
    latch.open("hello")
    let value = try await latch.wait()
    #expect(value == "hello")
  }

  @Test("wait suspends until open is called")
  func waitSuspendsUntilOpen() async throws {
    let latch = AsyncLatch<Int>()
    let resumed = ThreadSafe<Int?>(nil)

    let waiter = Task {
      let value = try await latch.wait()
      resumed(value)
    }

    for _ in 0..<10 { await Task.yield() }
    #expect(resumed() == nil)

    latch.open(7)
    try await waiter.value
    #expect(resumed() == 7)
  }

  @Test("multiple concurrent waiters all receive the stored value")
  func multipleWaitersAllReceiveValue() async throws {
    let latch = AsyncLatch<Int>()
    let received = ThreadSafe<[Int]>([])
    let waiterCount = 5

    try await withThrowingTaskGroup(of: Void.self) { group in
      for _ in 0..<waiterCount {
        group.addTask {
          let value = try await latch.wait()
          received { values in
            values.append(value)
          }
        }
      }

      for _ in 0..<10 { await Task.yield() }
      latch.open(99)
      try await group.waitForAll()
    }

    let values = received()
    #expect(values.count == waiterCount)
    #expect(values.allSatisfy { $0 == 99 })
  }

  @Test("repeated open without a close in between is a no-op")
  func repeatedOpenWithoutCloseIsNoOp() async throws {
    let latch = AsyncLatch<Int>()
    latch.open(1)
    latch.open(2)
    #expect(latch.openValue == 1)
    let value = try await latch.wait()
    #expect(value == 1)
  }

  @Test("close clears the stored value")
  func closeClearsValue() {
    let latch = AsyncLatch<Int>()
    latch.open(5)
    latch.close()
    #expect(!latch.isOpen)
    #expect(latch.openValue == nil)
  }

  @Test("open after close stores the new value")
  func openAfterCloseStoresNewValue() async throws {
    let latch = AsyncLatch<Int>()
    latch.open(1)
    latch.close()
    latch.open(2)
    #expect(latch.openValue == 2)
    let value = try await latch.wait()
    #expect(value == 2)
  }

  @Test("wait after close suspends until the next open")
  func waitAfterCloseSuspendsUntilNextOpen() async throws {
    let latch = AsyncLatch<Int>()
    latch.open(1)
    latch.close()

    let resumed = ThreadSafe<Int?>(nil)
    let waiter = Task {
      let value = try await latch.wait()
      resumed(value)
    }

    for _ in 0..<10 { await Task.yield() }
    #expect(resumed() == nil)

    latch.open(2)
    try await waiter.value
    #expect(resumed() == 2)
  }

  @Test("close does not retroactively unresume waiters resumed by a prior open")
  func closeDoesNotAffectAlreadyResumedWaiters() async throws {
    let latch = AsyncLatch<Int>()
    let resumed = ThreadSafe<Int?>(nil)

    let waiter = Task {
      let value = try await latch.wait()
      resumed(value)
    }

    for _ in 0..<10 { await Task.yield() }
    latch.open(11)
    try await waiter.value
    latch.close()

    #expect(resumed() == 11)
    #expect(!latch.isOpen)
  }

  @Test("close while waiters are suspended leaves them suspended")
  func closeLeavesSuspendedWaitersSuspended() async throws {
    let latch = AsyncLatch<Int>()
    let resumed = ThreadSafe<Int?>(nil)

    let waiter = Task {
      let value = try await latch.wait()
      resumed(value)
    }

    for _ in 0..<10 { await Task.yield() }
    latch.close()
    for _ in 0..<10 { await Task.yield() }
    #expect(resumed() == nil)

    latch.open(13)
    try await waiter.value
    #expect(resumed() == 13)
  }

  @Test("cancelling a waiting task throws CancellationError without opening the latch")
  func cancellationThrowsWithoutOpening() async {
    let latch = AsyncLatch<Int>()
    let caught = ThreadSafe<(any Error)?>(nil)

    let waiter = Task {
      do {
        _ = try await latch.wait()
      } catch {
        caught(error)
      }
    }

    for _ in 0..<10 { await Task.yield() }
    waiter.cancel()
    await waiter.value

    #expect(caught() is CancellationError)
    #expect(!latch.isOpen)
  }

  @Test("already-cancelled wait throws CancellationError without waiting for open")
  func alreadyCancelledWaitThrowsWithoutWaitingForOpen() async throws {
    let latch = AsyncLatch<Int>()
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    let waiting = ThreadSafe(false)
    let completed = ThreadSafe(false)
    let caught = ThreadSafe<(any Error)?>(nil)

    let waiter = Task {
      waiting(true)
      for await _ in stream {}
      #expect(Task.isCancelled)
      do {
        _ = try await latch.wait()
      } catch {
        caught(error)
      }
      completed(true)
    }

    try await Wait.until(
      maxAttempts: 50,
      { waiting() },
      { "Expected waiter to reach the pre-cancel gate" }
    )

    waiter.cancel()
    continuation.finish()

    do {
      try await Wait.until(
        maxAttempts: 50,
        { completed() },
        { "Expected already-cancelled waiter to complete without latch.open()" }
      )
    } catch {
      latch.open(0)
      await waiter.value
      throw error
    }

    await waiter.value
    #expect(caught() is CancellationError)
    #expect(!latch.isOpen)
  }
}
