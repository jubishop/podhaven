// Copyright Justin Bishop, 2026

import Foundation

protocol KeyValueStore: Sendable {
  func data(forKey defaultName: String) -> Data?
  func set(_ value: Any?, forKey defaultName: String)
  func removeObject(forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}
