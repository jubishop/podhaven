// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Property wrapper for simple read/write with UserDefaults persistence.
// Use when thread safety is already guaranteed by context (e.g. @MainActor).
@propertyWrapper
struct Persisted<T: DefaultsStorable> {
  private var value: T
  private let key: String
  private let store: any KeyValueStore

  init(
    wrappedValue: T,
    _ key: String,
    store: any KeyValueStore = Container.shared.standardDefaults()
  ) {
    self.key = key
    self.store = store
    value = T.load(from: store, forKey: key) ?? wrappedValue
  }

  var wrappedValue: T {
    get { value }
    set {
      value = newValue
      newValue.store(to: store, forKey: key)
    }
  }

  var projectedValue: Persisted<T> { self }

  // Re-reads the value from the backing store into the in-memory cache.
  // Use when another process may have written to the same store.
  mutating func refresh() {
    if let loaded = T.load(from: store, forKey: key) {
      value = loaded
    }
  }
}
