// Copyright Justin Bishop, 2025

import Foundation
import ErrorKit

extension AsyncSequence {
  func get() async throws -> Element {
    for try await value in self { return value }
    throw StateError.invalidState(description: "Sequence ended without yielding a value")
  }
}
