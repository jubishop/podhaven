// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Observation
import SwiftUI

// MARK: - BroadcastDuplicatePolicy

// Decides whether a write that produces an equal value still wakes observers.
// `.equatable` (the default for Equatable values) suppresses no-op writes;
// `.notifyAlways` is required for values whose `==` is not full observable
// equality — e.g. `OnDeck`, whose `==` ignores the `artwork`/`maxPlaybackTime`
// that `StateManager` mutates in place.
enum BroadcastDuplicatePolicy<T: Sendable>: Sendable {
  case notifyAlways
  case suppressDuplicates(@Sendable (T, T) -> Bool)

  fileprivate var isDuplicate: (@Sendable (T, T) -> Bool)? {
    switch self {
    case .notifyAlways: nil
    case .suppressDuplicates(let isDuplicate): isDuplicate
    }
  }
}

extension BroadcastDuplicatePolicy where T: Equatable {
  static var equatable: Self { .suppressDuplicates(==) }
}

// MARK: - Broadcast

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
  private let duplicatePolicy: BroadcastDuplicatePolicy<T>

  private struct State: Sendable {
    var current: T
    var continuations: [UUID: AsyncStream<T>.Continuation] = [:]
  }

  // MARK: - Initialization

  // Designated initializer with an explicit policy. The convenience
  // initializers below supply the per-type default — `.equatable` for
  // Equatable values, `.notifyAlways` otherwise — so most callers omit it.
  init(
    _ initialValue: T,
    policy: BroadcastDuplicatePolicy<T>,
    onChange: (@Sendable (T) -> Void)? = nil
  ) {
    state = ThreadSafe(State(current: initialValue))
    duplicatePolicy = policy
    self.onChange = onChange
  }

  // A non-Equatable value can't be compared, so it always notifies.
  convenience init(_ initialValue: T, onChange: (@Sendable (T) -> Void)? = nil) {
    self.init(initialValue, policy: .notifyAlways, onChange: onChange)
  }

  // MARK: - Current Value

  // Reading registers observation for SwiftUI views.
  var current: T {
    registrar.access(self, keyPath: \.current)
    return state().current
  }

  // Current value without Observation tracking — for hot paths that must not
  // register SwiftUI dependencies (e.g. swift-log sync policy on worker threads).
  var value: T {
    state().current
  }

  // MARK: - Broadcasting

  func new(_ value: T) {
    write { $0 = value }
  }

  func update(_ transform: (inout T) -> Void) {
    write(transform)
  }

  // The duplicate check runs inside the state lock so the compare and the
  // mutation+yield stay atomic — an outside check would race a concurrent
  // writer. `previous` is snapshotted only when the policy needs it, so a
  // `.notifyAlways` broadcast keeps mutating in place without an extra copy.
  private func write(_ transform: (inout T) -> Void) {
    let isDuplicate = duplicatePolicy.isDuplicate
    let broadcastValue: T? = state { state in
      if let isDuplicate {
        let previous = state.current
        transform(&state.current)
        guard !isDuplicate(previous, state.current) else { return nil }
      } else {
        transform(&state.current)
      }
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

  // MARK: - Binding

  // A SwiftUI two-way binding. The setter routes through `new`, so it honors
  // the broadcast's duplicate policy.
  var binding: Binding<T> {
    Binding(get: { self.current }, set: { self.new($0) })
  }
}

// MARK: - Equatable Default

extension Broadcast where T: Equatable {
  // Equatable values deduplicate no-op writes by default. Overload resolution
  // prefers this over the unconstrained initializer whenever `T: Equatable`.
  convenience init(_ initialValue: T, onChange: (@Sendable (T) -> Void)? = nil) {
    self.init(initialValue, policy: .equatable, onChange: onChange)
  }
}

// MARK: - Broadcasted

// Property wrapper that pairs a Broadcast with a clean read API.
// `wrappedValue` returns the current value (with SwiftUI observation),
// `projectedValue` ($property) exposes the Broadcast for .new(), .update(), .stream().
@propertyWrapper
struct Broadcasted<T: Sendable>: Sendable {
  private let broadcast: Broadcast<T>

  // Non-Equatable value: Broadcast's default policy is `.notifyAlways`.
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

extension Broadcasted where T: Equatable {
  // Equatable value: Broadcast's default policy is `.equatable`.
  init(wrappedValue: T) {
    broadcast = Broadcast(wrappedValue)
  }

  // Opt out (or supply a custom policy) for Equatable values whose `==` is not
  // full observable equality.
  init(wrappedValue: T, duplicates policy: BroadcastDuplicatePolicy<T>) {
    broadcast = Broadcast(wrappedValue, policy: policy)
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
