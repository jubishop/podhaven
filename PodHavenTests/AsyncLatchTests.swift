// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AsyncLatch tests")
struct AsyncLatchTests {
  @Test("isFinished is false on a fresh latch")
  func freshLatchIsNotFinished() {
    let latch = AsyncLatch<Void>()
    #expect(!latch.isFinished)
    #expect(latch.finishedValue == nil)
  }

  @Test("finish flips isFinished and exposes the value")
  func finishStoresValue() {
    let latch = AsyncLatch<Int>()
    latch.finish(42)
    #expect(latch.isFinished)
    #expect(latch.finishedValue == 42)
  }

  @Test("wait returns immediately on a pre-finished void latch")
  func waitReturnsImmediatelyWhenFinished() async throws {
    let latch = AsyncLatch<Void>()
    latch.finish()
    try await latch.wait()
  }

  @Test("wait returns the finished value on a pre-finished valued latch")
  func waitReturnsValue() async throws {
    let latch = AsyncLatch<String>()
    latch.finish("hello")
    let value = try await latch.wait()
    #expect(value == "hello")
  }

  @Test("wait suspends until finish is called")
  func waitSuspendsUntilFinish() async throws {
    let latch = AsyncLatch<Int>()
    let resumed = ThreadSafe<Int?>(nil)

    let waiter = Task {
      let value = try await latch.wait()
      resumed(value)
    }

    for _ in 0..<10 { await Task.yield() }
    #expect(resumed() == nil)

    latch.finish(7)
    try await waiter.value
    #expect(resumed() == 7)
  }

  @Test("multiple concurrent waiters all receive the finished value")
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
      latch.finish(99)
      try await group.waitForAll()
    }

    let values = received()
    #expect(values.count == waiterCount)
    #expect(values.allSatisfy { $0 == 99 })
  }

  @Test("second finish is a no-op — value does not change")
  func secondFinishIsNoOp() async throws {
    let latch = AsyncLatch<Int>()
    latch.finish(1)
    latch.finish(2)
    #expect(latch.finishedValue == 1)
    let value = try await latch.wait()
    #expect(value == 1)
  }

  @Test("cancelling a waiting task throws CancellationError without finishing the latch")
  func cancellationThrowsWithoutFinishing() async {
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
    #expect(!latch.isFinished)
  }

  @Test("already-cancelled wait throws CancellationError without waiting for finish")
  func alreadyCancelledWaitThrowsWithoutWaitingForFinish() async throws {
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
        { "Expected already-cancelled waiter to complete without latch.finish()" }
      )
    } catch {
      latch.finish(0)
      await waiter.value
      throw error
    }

    await waiter.value
    #expect(caught() is CancellationError)
    #expect(!latch.isFinished)
  }
}
