// Copyright Justin Bishop, 2026

import Foundation
import Observation
import SwiftUI

// A thread-safe, observable value holder that broadcasts changes to multiple
// async stream consumers and SwiftUI views.
//
// Usage:
// ```swift
// let broadcast = Broadcast<Int>(0)
//
// // Read current value (also registers SwiftUI observation)
// print(broadcast.current) // 0
//
// // Consumer (async stream)
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
final class Broadcast<T: Sendable>: Sendable, Observable {
  private let registrar = ObservationRegistrar()
  private let state: ThreadSafe<State>
  private let onChange: (@Sendable (T) -> Void)?

  private struct State: Sendable {
    var current: T
    var continuations: [UUID: AsyncStream<T>.Continuation] = [:]
  }

  // MARK: - Initialization

  init(_ initialValue: T, onChange: (@Sendable (T) -> Void)? = nil) {
    self.onChange = onChange
    state = ThreadSafe(State(current: initialValue))
  }

  // MARK: - Current Value

  // The current value held by the broadcast.
  // Reading this property registers observation for SwiftUI views.
  var current: T {
    registrar.access(self, keyPath: \.current)
    return state().current
  }

  // MARK: - Broadcasting

  // Replaces the current value entirely and broadcasts to all streams.
  func new(_ value: T) {
    registrar.withMutation(of: self, keyPath: \.current) {
      state { state in
        state.current = value
        for continuation in state.continuations.values {
          continuation.yield(value)
        }
      }
    }
    onChange?(value)
  }

  // Updates the current value using a closure and broadcasts the result.
  func update(_ transform: (inout T) -> Void) {
    let updated: T = registrar.withMutation(of: self, keyPath: \.current) {
      state { state in
        transform(&state.current)
        for continuation in state.continuations.values {
          continuation.yield(state.current)
        }
        return state.current
      }
    }
    onChange?(updated)
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

// Property wrapper that pairs a Broadcast with a clean read API.
// `wrappedValue` returns the current value (with SwiftUI observation),
// `projectedValue` ($property) exposes the Broadcast for .new(), .update(), .stream().
@propertyWrapper
struct ObservableBroadcast<T: Sendable>: Sendable {
  private let broadcast: Broadcast<T>

  init(wrappedValue: T) {
    broadcast = Broadcast(wrappedValue)
  }

  var wrappedValue: T {
    broadcast.current
  }

  var projectedValue: Broadcast<T> {
    broadcast
  }
}

// Property wrapper that pairs a Broadcast with UserDefaults persistence.
// Every mutation auto-persists via the onChange callback.
// In test context, skips UserDefaults to prevent cross-test contamination.
@propertyWrapper
struct PersistedBroadcast<T: DefaultsStorable>: Sendable {
  private let broadcast: Broadcast<T>

  init(wrappedValue: T, _ key: String) {
    if AppInfo.environment == .testing {
      broadcast = Broadcast(wrappedValue)
    } else {
      broadcast = Broadcast(T.load(from: UserDefaults.standard, forKey: key) ?? wrappedValue) {
        $0.store(to: UserDefaults.standard, forKey: key)
      }
    }
  }

  var wrappedValue: T {
    get { broadcast.current }
    nonmutating set { broadcast.new(newValue) }
  }

  var projectedValue: Broadcast<T> {
    broadcast
  }
}

// MARK: - Binding Support

extension Broadcast {
  @MainActor var binding: Binding<T> {
    Binding(get: { self.current }, set: { self.new($0) })
  }
}
