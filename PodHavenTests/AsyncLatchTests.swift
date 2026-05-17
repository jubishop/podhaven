// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AsyncLatch tests")
struct AsyncLatchTests {
  @Test("isTripped is false on a fresh latch")
  func freshLatchIsNotTripped() {
    let latch = AsyncLatch<Void>()
    #expect(!latch.isFinished)
    #expect(latch.finishedValue == nil)
  }

  @Test("trip flips isTripped and exposes the value")
  func tripStoresValue() {
    let latch = AsyncLatch<Int>()
    latch.finish(42)
    #expect(latch.isFinished)
    #expect(latch.finishedValue == 42)
  }

  @Test("wait returns immediately on a pre-tripped void latch")
  func waitReturnsImmediatelyWhenTripped() async throws {
    let latch = AsyncLatch<Void>()
    latch.finish()
    try await latch.wait()
  }

  @Test("wait returns the tripped value on a pre-tripped valued latch")
  func waitReturnsValue() async throws {
    let latch = AsyncLatch<String>()
    latch.finish("hello")
    let value = try await latch.wait()
    #expect(value == "hello")
  }

  @Test("wait suspends until trip is called")
  func waitSuspendsUntilTrip() async throws {
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

  @Test("multiple concurrent waiters all receive the tripped value")
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

  @Test("second trip is a no-op — value does not change")
  func secondTripIsNoOp() async throws {
    let latch = AsyncLatch<Int>()
    latch.finish(1)
    latch.finish(2)
    #expect(latch.finishedValue == 1)
    let value = try await latch.wait()
    #expect(value == 1)
  }

  @Test("cancelling a waiting task throws CancellationError without tripping the latch")
  func cancellationThrowsWithoutTripping() async {
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
}
