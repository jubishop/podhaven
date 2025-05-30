// Copyright Justin Bishop, 2025

import Foundation
import Sharing

@dynamicMemberLookup @propertyWrapper struct WrappedShared<Stored, Value> {
  @Shared private var storage: Stored
  private let get: (Stored) -> Value
  private let set: (Value) -> Stored

  init(
    _ storage: Shared<Stored>,
    get: @escaping (Stored) -> Value,
    set: @escaping (Value) -> Stored
  ) {
    self._storage = storage
    self.get = get
    self.set = set
  }

  var wrappedValue: Value {
    get { get(storage) }
    nonmutating set {
      $storage.withLock {
        $0 = set(newValue)
      }
    }
  }

  subscript<T>(dynamicMember keyPath: KeyPath<Value, T>) -> T {
    wrappedValue[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: WritableKeyPath<Value, T>) -> T {
    get { wrappedValue[keyPath: keyPath] }
    set { wrappedValue[keyPath: keyPath] = newValue }
  }
}
