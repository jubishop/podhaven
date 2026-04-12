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
  private let isLoading = ThreadLock()
  private let isRequesting = ThreadLock()

  init(embedding: any Embeddable) {
    self.embedding = embedding
  }

  var revision: Int { embedding.revision }
  var maximumSequenceLength: Int { embedding.maximumSequenceLength }

  func requestAndLoadAssetsIfNeeded() {
    guard !isAvailable else { return }

    guard embedding.hasAvailableAssets else {
      guard isRequesting.claim() else { return }

      Self.log.info("Requesting contextual embedding assets download")
      let isRequesting = isRequesting
      embedding.requestAssets { error in
        if let error {
          Self.log.caughtError("Failed to download contextual embedding assets", error)
          isRequesting.release()
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
      if var accumulated = sum {
        for i in 0..<vector.count { accumulated[i] += Float(vector[i]) }
        sum = accumulated
      } else {
        sum = vector.map { Float($0) }
      }
      count += 1
      return true
    }

    guard count > 0, let sum else { throw EmbeddingError.noResult }
    return sum.map { $0 / Float(count) }
  }

  fileprivate func loadAssets() {
    guard isLoading.claim() else { return }

    do {
      try embedding.load()
      isAvailable = true
    } catch {
      Self.log.caughtError("Failed to load contextual embedding", error)
      isLoading.release()
    }
  }
}
