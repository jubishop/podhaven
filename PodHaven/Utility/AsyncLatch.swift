// Copyright Justin Bishop, 2026

import Foundation

// Async gate with an optional payload. Initially closed; tasks awaiting
// `wait()` suspend until any caller invokes `open(_:)`, at which point all
// current and future awaiters receive the value. `close()` reverts to
// closed — previously-resumed waiters keep their value, but new `wait()`
// calls suspend again until the next `open(_:)`. Repeated `open(_:)` calls
// without a `close()` in between are no-ops, so callers that just need
// a one-shot signal (asset loading, download completion, initial sync
// result) can ignore `close()` entirely and treat this as monotonic.
// Cancellation of an awaiting task throws CancellationError and removes
// the continuation cleanly, so cancelled callers don't leak.
final class AsyncLatch<Value: Sendable>: Sendable {
  private struct State: Sendable {
    var value: Value?
    var continuations: [UUID: CheckedContinuation<Value, any Error>] = [:]
    var isOpen: Bool { value != nil }
  }

  private let state = ThreadSafe(State())

  init() {}

  var isOpen: Bool {
    state { $0.isOpen }
  }

  var openValue: Value? {
    state { $0.value }
  }

  func open(_ value: Value) {
    let pending: [CheckedContinuation<Value, any Error>] = state { s in
      guard !s.isOpen else { return [] }
      s.value = value
      let continuations = Array(s.continuations.values)
      s.continuations.removeAll()
      return continuations
    }
    for continuation in pending {
      continuation.resume(returning: value)
    }
  }

  // Clears the stored value so subsequent `wait()` calls suspend again.
  // Waiters that were already resumed by a prior `open(_:)` are unaffected.
  func close() {
    state { s in s.value = nil }
  }

  @discardableResult
  func wait() async throws -> Value {
    if let value = openValue { return value }

    let id = UUID()
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Value, any Error>) in
        let immediate: Result<Value, any Error>? = state { s in
          if let value = s.value { return .success(value) }
          if Task.isCancelled { return .failure(CancellationError()) }
          s.continuations[id] = continuation
          return nil
        }
        switch immediate {
        case .success(let value):
          continuation.resume(returning: value)
        case .failure(let error):
          continuation.resume(throwing: error)
        case nil:
          break
        }
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
  func open() {
    open(())
  }
}
