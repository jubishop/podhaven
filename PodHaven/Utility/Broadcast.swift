// Copyright Justin Bishop, 2026

import Foundation

// A thread-safe value holder that broadcasts changes to multiple async stream consumers.
//
// Usage:
// ```swift
// let broadcast = Broadcast<Int>(0)
//
// // Read current value
// print(broadcast.current) // 0
//
// // Consumer
// Task {
//   for await value in broadcast.stream() {
//     print("Received: \(value)")
//   }
// }
//
// // Replace value entirely
// broadcast.new(42)
//
// // Update value in place
// broadcast.update { $0 += 1 }
// ```
final class Broadcast<T: Sendable>: Sendable {
  private let state: ThreadSafe<State>

  private struct State: Sendable {
    var current: T
    var continuations: [UUID: AsyncStream<T>.Continuation] = [:]
  }

  // MARK: - Initialization

  init(_ initialValue: T) {
    state = ThreadSafe(State(current: initialValue))
  }

  // MARK: - Current Value

  // The current value held by the broadcast.
  var current: T {
    state().current
  }

  // MARK: - Broadcasting

  // Replaces the current value entirely and broadcasts to all streams.
  func new(_ value: T) {
    state { state in
      state.current = value
      for continuation in state.continuations.values {
        continuation.yield(value)
      }
    }
  }

  // Updates the current value using a closure and broadcasts the result.
  func update(_ transform: (inout T) -> Void) {
    state { state in
      transform(&state.current)
      for continuation in state.continuations.values {
        continuation.yield(state.current)
      }
    }
  }

  // MARK: - Streaming

  // Creates a new AsyncStream that immediately yields the current value,
  // then yields all future updates.
  func stream() -> AsyncStream<T> {
    let id = UUID()

    return AsyncStream { continuation in
      state { state in
        continuation.yield(state.current)
        state.continuations[id] = continuation
      }

      continuation.onTermination = { [weak self] _ in
        self?.state { _ = $0.continuations.removeValue(forKey: id) }
      }
    }
  }
}
