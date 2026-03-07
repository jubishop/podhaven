// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// Property wrapper for simple read/write with UserDefaults persistence.
// Use when thread safety is already guaranteed by context (e.g. @MainActor).
@propertyWrapper
struct Persisted<T: DefaultsStorable> {
  private var value: T
  private let key: String

  init(wrappedValue: T, _ key: String) {
    self.key = key
    value = T.load(from: Container.shared.standardDefaults(), forKey: key) ?? wrappedValue
  }

  var wrappedValue: T {
    get { value }
    set {
      value = newValue
      newValue.store(to: Container.shared.standardDefaults(), forKey: key)
    }
  }
}
