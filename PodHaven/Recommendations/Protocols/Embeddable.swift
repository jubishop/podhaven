// Copyright Justin Bishop, 2026

import Foundation
import NaturalLanguage

protocol Embeddable {
  var hasAvailableAssets: Bool { get }
  var revision: Int { get }
  func load() throws
  func requestAssets(
    completionHandler:
      @escaping @Sendable (NLContextualEmbedding.AssetsResult, (any Error)?) -> Void
  )
  func embeddingResult(for string: String) throws -> any EmbeddableResult
}

protocol EmbeddableResult {
  func enumerateTokenVectors(
    in range: Range<String.Index>,
    using block: ([Double], Range<String.Index>) -> Bool
  )
}
