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

// Actor so the synchronous NLContextualEmbedding work (BNNS-heavy
// embeddingResult, asset load) runs on the actor's executor instead of
// being pinned to a @MainActor caller's executor via the non-Sendable
// parameter.
actor ContextualEmbedding {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  // .requesting is sticky across a successful request → loadAssets sequence;
  // loadAssets() restores the prior state on failure so a post-request load
  // failure doesn't unblock a fresh download request.
  private enum AssetState {
    case idle
    case requesting
    case loading
  }

  nonisolated let assetsLoaded = AsyncLatch<Void>()
  nonisolated let revision: Int

  private let embedding: any Embeddable
  private var state: AssetState = .idle

  init(embedding: sending any Embeddable) {
    self.embedding = embedding
    revision = embedding.revision
  }

  func requestAndLoadAssetsIfNeeded() {
    loadAssetsIfAvailable()
    guard !embedding.hasAvailableAssets else { return }
    guard state == .idle else { return }
    state = .requesting

    Self.log.info("Requesting contextual embedding assets download")
    embedding.requestAssets { error in
      Task {
        await Container.shared.contextualEmbedding().completeAssetRequest(error: error)
      }
    }
  }

  // Load on-disk assets without triggering a download. Safe from a
  // BG-launched task handler where the scene never went active.
  func loadAssetsIfAvailable() {
    guard !assetsLoaded.isFinished, embedding.hasAvailableAssets else { return }
    loadAssets()
  }

  func vector(for text: String) throws -> [Float] {
    guard assetsLoaded.isFinished else { throw EmbeddingError.modelUnavailable }

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

  private func loadAssets() {
    guard state != .loading else { return }
    let prior = state
    state = .loading

    do {
      try embedding.load()
      assetsLoaded.finish()
    } catch {
      Self.log.caughtError("Failed to load contextual embedding", error)
      state = prior
    }
  }

  private func completeAssetRequest(error: (any Error)?) {
    if let error {
      Self.log.caughtError("Failed to download contextual embedding assets", error)
      state = .idle
    } else {
      Self.log.info("Contextual embedding assets downloaded")
      loadAssets()
    }
  }
}
