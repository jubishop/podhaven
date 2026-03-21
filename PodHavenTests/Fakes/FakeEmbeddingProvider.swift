// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeEmbeddingProvider: Embedding, Sendable {
  let revision: Int = 1
  let maximumInputLength: Int = 1000

  func vector(for text: String) throws -> [Float] {
    // Deterministic vector based on text hash
    let hash = abs(text.hashValue)
    return [
      Float(hash % 100) / 100.0,
      Float((hash / 100) % 100) / 100.0,
      Float((hash / 10000) % 100) / 100.0,
    ]
  }
}
