// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import NaturalLanguage

// MARK: - Container

extension Container {
  var embeddingProvider: Factory<(any Embeddable)?> {
    Factory(self) {
      if let existing = ContextualEmbedding.cached() { return existing }

      guard let embedding = NLContextualEmbedding(language: .english),
        embedding.hasAvailableAssets
      else {
        return nil
      }

      do {
        try embedding.load()
        let provider = ContextualEmbedding(nlEmbedding: embedding)
        ContextualEmbedding.cached(provider)
        return provider
      } catch {
        return nil
      }
    }
  }
}

enum EmbeddingError: LocalizedError {
  case noResult

  var errorDescription: String? {
    switch self {
    case .noResult:
      "Embedding produced no token vectors for the given text"
    }
  }
}

// MARK: - ContextualEmbedding

struct ContextualEmbedding: Embeddable, @unchecked Sendable {
  fileprivate static let cached = ThreadSafe<ContextualEmbedding?>(nil)

  private let nlEmbedding: NLContextualEmbedding

  fileprivate init(nlEmbedding: NLContextualEmbedding) {
    self.nlEmbedding = nlEmbedding
  }

  var revision: Int { nlEmbedding.revision }
  var maximumInputLength: Int { nlEmbedding.maximumSequenceLength }

  func vector(for text: String) throws -> [Float] {
    let result = try nlEmbedding.embeddingResult(for: text, language: .english)

    // Pool subword vectors by averaging
    var sum: [Float]?
    var count = 0

    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
      if sum == nil {
        sum = [Float](repeating: 0, count: vector.count)
      }
      for i in 0..<vector.count {
        sum![i] += Float(vector[i])
      }
      count += 1
      return true
    }

    guard count > 0, let sum else { throw EmbeddingError.noResult }
    return sum.map { $0 / Float(count) }
  }
}
