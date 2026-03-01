// Copyright Justin Bishop, 2026

import Foundation

protocol DefaultsStorable: Sendable {
  func store(to defaults: UserDefaults, forKey key: String)
  static func load(from defaults: UserDefaults, forKey key: String) -> Self?
}

// MARK: - Primitive Conformances

extension Bool: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    defaults.set(self, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Bool? {
    guard defaults.object(forKey: key) != nil else { return nil }
    return defaults.bool(forKey: key)
  }
}

extension Int: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    defaults.set(self, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Int? {
    guard defaults.object(forKey: key) != nil else { return nil }
    return defaults.integer(forKey: key)
  }
}

extension Double: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    defaults.set(self, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Double? {
    guard defaults.object(forKey: key) != nil else { return nil }
    return defaults.double(forKey: key)
  }
}

extension Float: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    defaults.set(self, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Float? {
    guard defaults.object(forKey: key) != nil else { return nil }
    return defaults.float(forKey: key)
  }
}

extension String: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    defaults.set(self, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> String? {
    defaults.string(forKey: key)
  }
}

// MARK: - Optional Conformance

extension Optional: DefaultsStorable where Wrapped: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    if let value = self {
      value.store(to: defaults, forKey: key)
    } else {
      defaults.removeObject(forKey: key)
    }
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Wrapped?? {
    guard defaults.object(forKey: key) != nil else { return nil }
    return Wrapped.load(from: defaults, forKey: key)
  }
}

// MARK: - RawRepresentable Conformance

extension DefaultsStorable where Self: RawRepresentable, RawValue: DefaultsStorable {
  func store(to defaults: UserDefaults, forKey key: String) {
    rawValue.store(to: defaults, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Self? {
    guard let rawValue = RawValue.load(from: defaults, forKey: key) else { return nil }
    return Self(rawValue: rawValue)
  }
}

// MARK: - Codable Conformance

extension DefaultsStorable where Self: Codable {
  func store(to defaults: UserDefaults, forKey key: String) {
    guard let data = try? JSONEncoder().encode(self) else { return }
    defaults.set(data, forKey: key)
  }

  static func load(from defaults: UserDefaults, forKey key: String) -> Self? {
    guard let data = defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Self.self, from: data)
  }
}
