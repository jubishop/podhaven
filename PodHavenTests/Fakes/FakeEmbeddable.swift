// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

struct FakeEmbeddable: Embeddable {
  var hasAvailableAssets = true
  let revision: Int = 1

  func load() throws {}

  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    completion(nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    // Deterministic vector based on text hash
    let hash = abs(string.hashValue)
    let vector: [Double] = [
      Double(hash % 100) / 100.0,
      Double((hash / 100) % 100) / 100.0,
      Double((hash / 10000) % 100) / 100.0,
    ]
    return FakeEmbeddingResult(vectors: [vector])
  }
}

struct FakeEmbeddingResult: EmbeddableResult {
  let vectors: [[Double]]

  func enumerateTokenVectors(
    in range: Range<String.Index>,
    using block: ([Double], Range<String.Index>) -> Bool
  ) {
    for vector in vectors where !block(vector, range) {
      break
    }
  }
}
