#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation

@dynamicMemberLookup
struct SendableBox<T>: @unchecked Sendable {
  let value: T

  init(_ value: T) {
    self.value = value
  }

  subscript<U>(dynamicMember keyPath: KeyPath<T, U>) -> U {
    value[keyPath: keyPath]
  }
}
#endif
