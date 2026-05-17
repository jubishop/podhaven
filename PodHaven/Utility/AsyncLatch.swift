// Copyright Justin Bishop, 2026

import Foundation

// One-shot async latch. Initially open; tasks awaiting `wait()` suspend
// until any caller invokes `finish(_:)`, at which point all current and
// future awaiters receive the finished value. A finished latch stays
// finished — unlike AsyncSemaphore, which decrements per signal, this is
// monotonic. Cancellation of an awaiting task throws CancellationError
// and removes the continuation cleanly, so cancelled callers don't leak.
//
// Use for "wait until a one-time setup is done" with an optional payload:
// asset loading, download completion, initial sync result. For repeated
// signaling, use AsyncStream or @Broadcasted.
final class AsyncLatch<Value: Sendable>: Sendable {
  private struct State: Sendable {
    var value: Value?
    var continuations: [UUID: CheckedContinuation<Value, any Error>] = [:]
    var isFinished: Bool { value != nil }
  }

  private let state = ThreadSafe(State())

  init() {}

  var isFinished: Bool {
    state { $0.isFinished }
  }

  var finishedValue: Value? {
    state { $0.value }
  }

  func finish(_ value: Value) {
    let pending: [CheckedContinuation<Value, any Error>] = state { s in
      guard !s.isFinished else { return [] }
      s.value = value
      let continuations = Array(s.continuations.values)
      s.continuations.removeAll()
      return continuations
    }
    for continuation in pending {
      continuation.resume(returning: value)
    }
  }

  @discardableResult
  func wait() async throws -> Value {
    if let value = finishedValue { return value }

    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Value, any Error>) in
        let immediate: Value? = state { s in
          if let value = s.value { return value }
          s.continuations[id] = continuation
          return nil
        }
        if let immediate { continuation.resume(returning: immediate) }
      }
    } onCancel: {
      let continuation: CheckedContinuation<Value, any Error>? = state { s in
        s.continuations.removeValue(forKey: id)
      }
      continuation?.resume(throwing: CancellationError())
    }
  }
}

extension AsyncLatch where Value == Void {
  func finish() {
    finish(())
  }
}
