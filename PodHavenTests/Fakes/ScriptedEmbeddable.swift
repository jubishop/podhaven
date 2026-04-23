// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// Embeddable whose output is driven by a caller-supplied closure so tests
// can engineer specific similarity relationships between signals and candidates.
// `FakeEmbeddable` hashes the string to produce a pseudo-random vector, which
// makes similarity-based behavior untestable.
struct ScriptedEmbeddable: Embeddable {
  var hasAvailableAssets = true
  let revision: Int = 1

  let vectorFor: @Sendable (String) -> [Double]

  init(defaultVector: [Double] = [1, 0, 0], vectorFor: @escaping @Sendable (String) -> [Double]) {
    self.vectorFor = { text in
      let vector = vectorFor(text)
      return vector.isEmpty ? defaultVector : vector
    }
  }

  func load() throws {}

  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    completion(nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    FakeEmbeddingResult(vectors: [vectorFor(string)])
  }
}
