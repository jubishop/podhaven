// Copyright Justin Bishop, 2026

import FactoryKit
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
    state = ThreadSafe(State(current: initialValue))
    self.onChange = onChange
  }

  // MARK: - Current Value

  // Reading registers observation for SwiftUI views.
  var current: T {
    registrar.access(self, keyPath: \.current)
    return state().current
  }

  // MARK: - Broadcasting

  func new(_ value: T) {
    write({ $0 = value }, isDuplicate: nil)
  }

  func update(_ transform: (inout T) -> Void) {
    write(transform, isDuplicate: nil)
  }

  // `isDuplicate` is checked inside the state lock so the compare and the
  // mutation+yield are atomic — an outside check would race a concurrent writer.
  private func write(
    _ transform: (inout T) -> Void,
    isDuplicate: ((T, T) -> Bool)?
  ) {
    let broadcastValue: T? = state { state in
      let previous = state.current
      transform(&state.current)
      if let isDuplicate, isDuplicate(previous, state.current) { return nil }
      for continuation in state.continuations.values {
        continuation.yield(state.current)
      }
      return state.current
    }
    guard let broadcastValue else { return }
    notifyObservers(broadcastValue)
  }

  // Hop to MainActor so SwiftUI picks up the change regardless of which thread mutated.
  private func notifyObservers(_ value: T) {
    onChange?(value)
    Task { @MainActor [weak self] in
      guard let self else { return }
      registrar.withMutation(of: self, keyPath: \.current) {}
    }
  }

  // MARK: - Streaming

  // Yields the current value immediately, then every future update.
  // Callers that don't want the bootstrap emit can chain `.dropFirst()`.
  func stream() -> AsyncStream<T> {
    let id = UUID()

    return AsyncStream { continuation in
      state { state in
        continuation.yield(state.current)
        state.continuations[id] = continuation
      }

      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        self.state { _ = $0.continuations.removeValue(forKey: id) }
      }
    }
  }
}

// MARK: - Equatable Deduplication

// Equatable values are deduplicated: a write that doesn't change the value
// wakes no stream or SwiftUI observer. Overload resolution prefers these over
// the unconstrained `new`/`update` whenever `T: Equatable`.
extension Broadcast where T: Equatable {
  func new(_ value: T) {
    write({ $0 = value }, isDuplicate: ==)
  }

  func update(_ transform: (inout T) -> Void) {
    write(transform, isDuplicate: ==)
  }
}

// Property wrapper that pairs a Broadcast with a clean read API.
// `wrappedValue` returns the current value (with SwiftUI observation),
// `projectedValue` ($property) exposes the Broadcast for .new(), .update(), .stream().
@propertyWrapper
struct Broadcasted<T: Sendable>: Sendable {
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

// MARK: - Binding Support

extension Broadcast {
  @MainActor var binding: Binding<T> {
    Binding(get: { self.current }, set: { self.new($0) })
  }
}

// MARK: - PersistedBroadcast

// Property wrapper that pairs a Broadcast with UserDefaults persistence.
// Every mutation auto-persists via the onChange callback.
// In test context, uses injected FakeKeyValueStore to prevent cross-test contamination.
@propertyWrapper
struct PersistedBroadcast<T: DefaultsStorable>: Sendable {
  private let broadcast: Broadcast<T>

  init(
    wrappedValue: T,
    _ key: String,
    store: any KeyValueStore = Container.shared.standardDefaults(),
    onChange: (@Sendable (T) -> Void)? = nil
  ) {
    broadcast = Broadcast(T.load(from: store, forKey: key) ?? wrappedValue) {
      $0.store(to: store, forKey: key)
      onChange?($0)
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
