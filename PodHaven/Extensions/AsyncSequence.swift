// Copyright Justin Bishop, 2025

import Foundation

extension AsyncSequence {
  func get() async throws -> Element {
    for try await value in self { return value }
    Log.fatal("Sequence ended without yielding a value")
  }
}
