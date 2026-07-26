// Copyright Justin Bishop, 2026

import Foundation
import Testing

@testable import PodHaven

@Suite("of PersistedThreadSafe")
struct PersistedThreadSafeTests {
  @Test("same-value assignments do not write")
  func sameValueAssignmentsDoNotWrite() {
    let store = WriteCountingKeyValueStore()
    let value = PersistedThreadSafe(wrappedValue: 1, "value", store: store)

    value.wrappedValue = 1
    value.wrappedValue = 2
    value.wrappedValue = 2

    #expect(store.writeCount == 1)
    #expect(Int.load(from: store, forKey: "value") == 2)
  }

  @Test("atomic updates persist only changed values")
  func atomicUpdatesPersistOnlyChanges() {
    let store = WriteCountingKeyValueStore()
    let value = PersistedThreadSafe(wrappedValue: 1, "value", store: store)

    value.update { $0 += 1 }
    value.update { _ in }

    #expect(value.wrappedValue == 2)
    #expect(store.writeCount == 1)
  }
}

private final class WriteCountingKeyValueStore: KeyValueStore {
  private struct State {
    var data: [String: Data] = [:]
    var writeCount = 0
  }

  private let state = ThreadSafe(State())

  var allKeys: [String] {
    Array(state().data.keys)
  }

  var writeCount: Int {
    state().writeCount
  }

  func data(forKey defaultName: String) -> Data? {
    state().data[defaultName]
  }

  func string(forKey _: String) -> String? {
    nil
  }

  func set(_ value: Any?, forKey defaultName: String) {
    state { state in
      state.writeCount += 1
      if let data = value as? Data {
        state.data[defaultName] = data
      } else {
        state.data.removeValue(forKey: defaultName)
      }
    }
  }

  func removeObject(forKey defaultName: String) {
    state { state in
      state.data.removeValue(forKey: defaultName)
    }
  }
}
