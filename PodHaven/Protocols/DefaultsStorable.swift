// Copyright Justin Bishop, 2026

import Foundation

protocol DefaultsStorable: Sendable {
  func store(to store: any KeyValueStore, forKey key: String)
  static func load(from store: any KeyValueStore, forKey key: String) -> Self?
}

// MARK: - Primitive Conformances

extension Bool: DefaultsStorable {}
extension Int: DefaultsStorable {}
extension Double: DefaultsStorable {}
extension Float: DefaultsStorable {}
extension String: DefaultsStorable {}

// MARK: - Optional Conformance

extension Optional: DefaultsStorable where Wrapped: DefaultsStorable {
  func store(to store: any KeyValueStore, forKey key: String) {
    if let value = self {
      value.store(to: store, forKey: key)
    } else {
      store.removeObject(forKey: key)
    }
  }

  static func load(from store: any KeyValueStore, forKey key: String) -> Wrapped?? {
    guard store.data(forKey: key) != nil else { return nil }
    return Wrapped.load(from: store, forKey: key)
  }
}

// MARK: - Codable Conformance

extension DefaultsStorable where Self: Codable {
  func store(to store: any KeyValueStore, forKey key: String) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    store.set(data, forKey: key)
  }

  static func load(from store: any KeyValueStore, forKey key: String) -> Self? {
    guard let data = store.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}
