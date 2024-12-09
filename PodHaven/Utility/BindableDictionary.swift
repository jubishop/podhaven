// Copyright Justin Bishop, 2024

import Foundation

@Observable @MainActor
final class BindableDictionary<Key: Hashable, Value>: Sendable {
  private var dictionary: [Key: Value] = [:]
  private let defaultValue: Value

  init(defaultValue: Value) {
    self.defaultValue = defaultValue
  }

  subscript(key: Key) -> Value {
    get { dictionary[key, default: defaultValue] }
    set { dictionary[key] = newValue }
  }
}
