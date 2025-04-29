// Copyright Justin Bishop, 2025

import Foundation

extension AsyncSequence {
  func get() async throws -> Element {
    for try await value in self { return value }
    throw Err("Sequence ended without yielding a value")
  }
}
