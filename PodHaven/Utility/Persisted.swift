// Copyright Justin Bishop, 2026

import Foundation

// MARK: - PersistedThreadSafe

// Property wrapper that pairs a ThreadSafe with UserDefaults persistence.
// Use instead of PersistedBroadcast when SwiftUI observation and
// AsyncStream are not needed — just thread-safe read/write with persistence.
@propertyWrapper
struct PersistedThreadSafe<T: DefaultsStorable>: Sendable {
  private let storage: ThreadSafe<T>
  private let key: String

  init(wrappedValue: T, _ key: String) {
    self.key = key
    if AppInfo.environment == .testing {
      storage = ThreadSafe(wrappedValue)
    } else {
      storage = ThreadSafe(T.load(from: UserDefaults.standard, forKey: key) ?? wrappedValue)
    }
  }

  var wrappedValue: T {
    get { storage() }
    nonmutating set {
      storage(newValue)
      if AppInfo.environment != .testing {
        newValue.store(to: UserDefaults.standard, forKey: key)
      }
    }
  }
}

// MARK: - PersistedBroadcast

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
