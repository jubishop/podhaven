#if DEBUG
// Copyright Justin Bishop, 2026

import Foundation
import NaturalLanguage

// Embeddable whose output is driven by a caller-supplied closure so previews
// can engineer specific similarity relationships between signals and
// candidates without loading the real NLContextualEmbedding model.
struct PreviewEmbeddable: Embeddable {
  let hasAvailableAssets = true
  let revision: Int = 1

  private let vectorFor: @Sendable (String) -> [Double]

  init(vectorFor: @escaping @Sendable (String) -> [Double]) {
    self.vectorFor = vectorFor
  }

  func load() throws {}

  func requestAssets(
    completionHandler completion:
      @escaping @Sendable (NLContextualEmbedding.AssetsResult, (any Error)?) -> Void
  ) {
    completion(hasAvailableAssets ? .available : .notAvailable, nil)
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    PreviewEmbeddingResult(vector: vectorFor(string))
  }
}

struct PreviewEmbeddingResult: EmbeddableResult {
  let vector: [Double]

  func enumerateTokenVectors(
    in range: Range<String.Index>,
    using block: ([Double], Range<String.Index>) -> Bool
  ) {
    _ = block(vector, range)
  }
}
#endif
