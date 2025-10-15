// Copyright Justin Bishop, 2025

import Foundation

@Observable
class BindableDictionary<Key: Hashable, Value>: Sequence {
  private var dictionary: [Key: Value] = [:]
  private let defaultValue: Value

  init(defaultValue: Value) {
    self.defaultValue = defaultValue
  }

  var values: [Value] { Array(dictionary.values) }
  var keys: [Key] { Array(dictionary.keys) }

  subscript(key: Key) -> Value {
    get { dictionary[key, default: defaultValue] }
    set { dictionary[key] = newValue }
  }

  func makeIterator() -> Dictionary<Key, Value>.Iterator {
    dictionary.makeIterator()
  }

  func removeAll(keepingCapacity keepCapacity: Bool = false) {
    dictionary.removeAll(keepingCapacity: keepCapacity)
  }

  func removeAll(where shouldRemove: (Key, Value) throws -> Bool) rethrows {
    for (key, value) in dictionary where try shouldRemove(key, value) {
      dictionary.removeValue(forKey: key)
    }
  }

  @discardableResult
  func removeValue(forKey key: Key) -> Value? {
    dictionary.removeValue(forKey: key)
  }
}
