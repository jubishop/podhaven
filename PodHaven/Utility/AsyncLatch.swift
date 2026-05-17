// Copyright Justin Bishop, 2026

import Foundation

// One-shot async latch. Initially closed; tasks awaiting `wait()` suspend
// until any caller invokes `trip(_:)`, at which point all current and
// future awaiters receive the tripped value. A tripped latch stays
// tripped — unlike AsyncSemaphore, which decrements per signal, this is
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
    var isTripped: Bool { value != nil }
  }

  private let state = ThreadSafe(State())

  init() {}

  var isTripped: Bool {
    state { $0.isTripped }
  }

  var trippedValue: Value? {
    state { $0.value }
  }

  func trip(_ value: Value) {
    let pending: [CheckedContinuation<Value, any Error>] = state { s in
      guard !s.isTripped else { return [] }
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
    if let value = trippedValue { return value }

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
  func trip() {
    trip(())
  }
}
