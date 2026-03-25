// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

final class FakeKeyValueStore: KeyValueStore {
  private let storage = ThreadSafe<[String: Data]>([:])

  var allKeys: [String] {
    Array(storage().keys)
  }

  func data(forKey defaultName: String) -> Data? {
    storage()[defaultName]
  }

  func set(_ value: Any?, forKey defaultName: String) {
    if let data = value as? Data {
      storage { $0[defaultName] = data }
    } else {
      storage { $0.removeValue(forKey: defaultName) }
    }
  }

  func removeObject(forKey defaultName: String) {
    storage { $0.removeValue(forKey: defaultName) }
  }
}
