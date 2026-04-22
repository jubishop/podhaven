// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import NaturalLanguage

// MARK: - Container

extension Container {
  var nlContextualEmbedding: Factory<any Embeddable> {
    Factory(self) {
      guard let embedding = NLContextualEmbedding(language: .english) else {
        Assert.fatal("NLContextualEmbedding(language: .english) returned nil")
      }
      return embedding
    }
  }
}

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
