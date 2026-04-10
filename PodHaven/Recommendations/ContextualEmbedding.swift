// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import NaturalLanguage

// MARK: - Container

extension Container {
  var contextualEmbedding: Factory<ContextualEmbedding> {
    Factory(self) { ContextualEmbedding(embedding: self.nlContextualEmbedding()) }
      .scope(.cached)
  }
}

// MARK: - Errors

enum EmbeddingError: LocalizedError {
  case modelUnavailable
  case noResult

  var errorDescription: String? {
    switch self {
    case .modelUnavailable:
      "Contextual embedding model is not available"
    case .noResult:
      "Embedding produced no token vectors for the given text"
    }
  }
}

// MARK: - ContextualEmbedding

class ContextualEmbedding {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  private(set) var isAvailable = false

  private let embedding: any Embeddable
  private let isLoading = ThreadSafe(false)
  private let isRequesting = ThreadSafe(false)

  init(embedding: any Embeddable) {
    self.embedding = embedding
  }

  var revision: Int { embedding.revision }
  var maximumSequenceLength: Int { embedding.maximumSequenceLength }

  func requestAndLoadAssetsIfNeeded() {
    guard !isAvailable else { return }

    guard embedding.hasAvailableAssets else {
      let shouldRequest = isRequesting { requesting -> Bool in
        guard !requesting else { return false }
        requesting = true
        return true
      }
      guard shouldRequest else { return }

      Self.log.info("Requesting contextual embedding assets download")
      let isRequesting = isRequesting
      embedding.requestAssets { error in
        if let error {
          Self.log.caughtError("Failed to download contextual embedding assets", error)
          isRequesting(false)
        } else {
          Self.log.info("Contextual embedding assets downloaded")
          Container.shared.contextualEmbedding().loadAssets()
        }
      }
      return
    }

    loadAssets()
  }

  func vector(for text: String) throws -> [Float] {
    guard isAvailable else { throw EmbeddingError.modelUnavailable }

    let result = try embedding.embeddingResult(for: text)

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

  fileprivate func loadAssets() {
    let shouldLoad = isLoading { loading -> Bool in
      guard !loading else { return false }
      loading = true
      return true
    }
    guard shouldLoad else { return }

    do {
      try embedding.load()
      isAvailable = true
    } catch {
      Self.log.caughtError("Failed to load contextual embedding", error)
      isLoading(false)
    }
  }
}
