// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of AsyncSequence tests")
struct AsyncSequenceTests {
  @Test("get() returns the first value")
  func getReturnsFirstValue() async throws {
    let (stream, continuation) = AsyncStream<Int>.makeStream()
    continuation.yield(1)
    continuation.yield(2)

    #expect(try await stream.get() == 1)
  }

  @Test("get() throws CancellationError when cancellation ends the sequence")
  func getThrowsWhenCancelled() async throws {
    let (started, startedContinuation) = AsyncStream<Void>.makeStream()
    let task = Task {
      let stream = AsyncStream<Int> { _ in startedContinuation.finish() }
      return try await stream.get()
    }
    for await _ in started {}
    task.cancel()

    await #expect(throws: CancellationError.self) { try await task.value }
  }
}
