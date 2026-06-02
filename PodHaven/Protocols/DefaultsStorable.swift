// Copyright Justin Bishop, 2026

import Foundation
import Logging

private let defaultsStorableLog = Log.as("DefaultsStorable")

protocol DefaultsStorable: Sendable, Equatable {
  func store(to store: any KeyValueStore, forKey key: String)
  static func load(from store: any KeyValueStore, forKey key: String) -> Self?
}

// MARK: - Primitive Conformances

extension Bool: DefaultsStorable {}
extension Int: DefaultsStorable {}
extension Double: DefaultsStorable {}
extension Float: DefaultsStorable {}
extension String: DefaultsStorable {}
extension Date: DefaultsStorable {}

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

// MARK: - Array Conformance

// An array of storable, Codable elements persists as a single JSON blob via the
// Codable default implementation below.
extension Array: DefaultsStorable where Element: DefaultsStorable & Codable {}

// MARK: - Codable Conformance

extension DefaultsStorable where Self: Codable {
  func store(to store: any KeyValueStore, forKey key: String) {
    do {
      let data = try JSONEncoder().encode(self)
      store.set(data, forKey: key)
    } catch {
      defaultsStorableLog.caughtError(
        "store: failed to encode \(Self.self) for key '\(key)'",
        error
      )
    }
  }

  static func load(from store: any KeyValueStore, forKey key: String) -> Self? {
    guard let data = store.data(forKey: key) else { return nil }
    do {
      return try JSONDecoder().decode(Self.self, from: data)
    } catch {
      defaultsStorableLog.caughtError(
        "load: failed to decode \(Self.self) for key '\(key)', clearing stale value",
        error
      )
      store.removeObject(forKey: key)
      return nil
    }
  }
}
