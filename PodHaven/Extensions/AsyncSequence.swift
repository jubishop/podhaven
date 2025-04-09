// Copyright Justin Bishop, 2025 

import Foundation

extension AsyncSequence {
  func first() async throws -> Element {
    for try await value in self {
      return value
    }
    throw Err.msg("Sequence ended without yielding a value")
  }
}
