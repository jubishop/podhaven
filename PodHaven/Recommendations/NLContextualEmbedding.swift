// Copyright Justin Bishop, 2026

import Foundation
import NaturalLanguage

// MARK: - NLContextualEmbedding + Embeddable

extension NLContextualEmbedding: Embeddable {
  func requestAssets(completion: @escaping @Sendable ((any Error)?) -> Void) {
    requestAssets { _, error in completion(error) }
  }

  func embeddingResult(for string: String) throws -> any EmbeddableResult {
    try embeddingResult(for: string, language: .english)
  }
}

// MARK: - NLContextualEmbeddingResult + EmbeddableResult

extension NLContextualEmbeddingResult: EmbeddableResult {}
