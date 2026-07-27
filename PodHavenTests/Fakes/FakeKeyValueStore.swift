// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

final class FakeKeyValueStore: KeyValueStore {
  private struct State {
    var data: [String: Data] = [:]
    var strings: [String: String] = [:]
  }

  private let state = ThreadSafe(State())

  var allKeys: [String] {
    let state = state()
    return Array(Set(state.data.keys).union(state.strings.keys))
  }

  func data(forKey defaultName: String) -> Data? {
    state().data[defaultName]
  }

  func string(forKey defaultName: String) -> String? {
    state().strings[defaultName]
  }

  func set(_ value: Any?, forKey defaultName: String) {
    state { state in
      if let data = value as? Data {
        state.data[defaultName] = data
        state.strings.removeValue(forKey: defaultName)
      } else if let string = value as? String {
        state.strings[defaultName] = string
        state.data.removeValue(forKey: defaultName)
      } else {
        state.data.removeValue(forKey: defaultName)
        state.strings.removeValue(forKey: defaultName)
      }
    }
  }

  func removeObject(forKey defaultName: String) {
    state { state in
      state.data.removeValue(forKey: defaultName)
      state.strings.removeValue(forKey: defaultName)
    }
  }
}
