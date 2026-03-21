// Copyright Justin Bishop, 2026

import CryptoKit
import FactoryKit
import Foundation
import Logging
import NaturalLanguage

// MARK: - Embedding Protocol

protocol Embedding: Sendable {
  func vector(for text: String) throws -> [Float]
  var revision: Int { get }
  var maximumInputLength: Int { get }
}

// MARK: - Container

extension Container {
  var embeddingService: Factory<EmbeddingService> {
    Factory(self) { EmbeddingService() }.scope(.cached)
  }

  var embeddingProvider: Factory<(any Embedding)?> {
    Factory(self) { nil }
  }
}

// MARK: - EmbeddingService

struct EmbeddingService: Sendable {
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  // Title gets more weight than description to avoid boilerplate dominance
  private static let titleWeight: Float = 0.6
  private static let descriptionWeight: Float = 0.4

  // Podcast description blending ratio
  private static let episodeBlendWeight: Float = 0.6
  private static let podcastBlendWeight: Float = 0.4

  // MARK: - Embedding Provider

  func resolveEmbedding() -> (any Embedding)? {
    if let override = Container.shared.embeddingProvider() {
      return override
    }
    return ContextualEmbeddingProvider.createIfAvailable()
  }

  // MARK: - Request Assets

  func requestContextualAssetsIfNeeded() {
    guard let embedding = NLContextualEmbedding(language: .english) else { return }
    if !embedding.hasAvailableAssets {
      Self.log.info("Requesting contextual embedding assets download")
      embedding.requestAssets { result, error in
        if let error {
          Self.log.caughtError("Failed to download contextual embedding assets", error)
        } else {
          Self.log.info("Contextual embedding assets result: \(result)")
        }
      }
    }
  }

  // MARK: - Compute Episode Embedding

  func computeEmbedding(for episode: Episode, embedding: any Embedding) async throws -> [Float] {
    let cleanedTitle = cleanText(episode.title)
    let cleanedDescription = cleanText(episode.description ?? "")

    let titleVector = try embedding.vector(for: cleanedTitle)

    let descriptionText =
      cleanedDescription.isEmpty
      ? cleanedTitle
      : String(cleanedDescription.prefix(embedding.maximumInputLength))
    let descriptionVector = try embedding.vector(for: descriptionText)

    // Weighted average of title and description
    var episodeVector = weightedAverage(
      titleVector,
      weight1: Self.titleWeight,
      descriptionVector,
      weight2: Self.descriptionWeight
    )

    // Blend with podcast description embedding
    let podcastVector = try await fetchOrComputePodcastEmbedding(
      podcastID: episode.podcastID,
      embedding: embedding
    )
    if let podcastVector {
      episodeVector = weightedAverage(
        episodeVector,
        weight1: Self.episodeBlendWeight,
        podcastVector,
        weight2: Self.podcastBlendWeight
      )
    }

    return normalize(episodeVector)
  }

  // MARK: - Podcast Embedding

  private func fetchOrComputePodcastEmbedding(
    podcastID: Podcast.ID,
    embedding: any Embedding
  ) async throws -> [Float]? {
    if let cached = try await repo.fetchPodcastEmbedding(for: podcastID) {
      return cached.floatVector
    }

    guard let podcast = try await repo.fetchPodcast(podcastID) else { return nil }

    let cleanedDescription = cleanText(podcast.description)
    guard !cleanedDescription.isEmpty else { return nil }

    let text = String(cleanedDescription.prefix(embedding.maximumInputLength))
    let vector = try embedding.vector(for: text)
    let normalized = normalize(vector)

    let podcastEmbedding = PodcastEmbedding(
      podcastId: podcastID,
      vector: PodcastEmbedding.vectorData(from: normalized),
      sourceHash: sha256(cleanedDescription),
      embeddingRevision: embedding.revision,
      dimension: normalized.count,
      computedAt: Date()
    )
    try await repo.savePodcastEmbedding(podcastEmbedding)

    return normalized
  }

  // MARK: - Ensure Embeddings

  func ensureEmbeddings(
    for episodes: [Episode],
    embedding: any Embedding,
    checkCancellation: Bool = true
  ) async throws {
    for episode in episodes {
      if checkCancellation { try Task.checkCancellation() }

      let existingEmbedding = try await repo.fetchEmbedding(for: episode.id)
      let sourceText = embeddingSourceText(for: episode)
      let hash = sha256(sourceText)

      let needsRecompute =
        existingEmbedding == nil
        || existingEmbedding?.sourceHash != hash

      guard needsRecompute else { continue }

      let vector = try await computeEmbedding(for: episode, embedding: embedding)

      let episodeEmbedding = EpisodeEmbedding(
        episodeId: episode.id,
        vector: EpisodeEmbedding.vectorData(from: vector),
        sourceHash: hash,
        embeddingRevision: embedding.revision,
        dimension: vector.count,
        computedAt: Date()
      )
      try await repo.saveEmbedding(episodeEmbedding)
    }
  }

  // MARK: - Text Cleaning

  func cleanText(_ text: String) -> String {
    var result = text

    // Strip HTML tags
    result = result.replacingOccurrences(
      of: "<[^>]+>",
      with: " ",
      options: .regularExpression
    )

    // Strip URLs
    result = result.replacingOccurrences(
      of: "https?://\\S+",
      with: "",
      options: .regularExpression
    )

    // Strip timestamps (same pattern the app uses for chapter parsing)
    result = result.replacingOccurrences(
      of: "\\d{1,2}:\\d{2}(:\\d{2})?",
      with: "",
      options: .regularExpression
    )

    // Normalize whitespace
    result = result.replacingOccurrences(
      of: "\\s+",
      with: " ",
      options: .regularExpression
    )

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - Vector Math

  func weightedAverage(
    _ v1: [Float],
    weight1: Float,
    _ v2: [Float],
    weight2: Float
  ) -> [Float] {
    guard v1.count == v2.count else {
      Assert.fatal("Vector dimension mismatch: \(v1.count) vs \(v2.count)")
    }
    return zip(v1, v2).map { a, b in a * weight1 + b * weight2 }
  }

  func normalize(_ vector: [Float]) -> [Float] {
    let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    guard norm > 0 else { return vector }
    return vector.map { $0 / norm }
  }

  func dotProduct(_ v1: [Float], _ v2: [Float]) -> Float {
    guard v1.count == v2.count else {
      Assert.fatal("Vector dimension mismatch: \(v1.count) vs \(v2.count)")
    }
    return zip(v1, v2).reduce(0) { $0 + $1.0 * $1.1 }
  }

  // MARK: - Helpers

  func embeddingSourceText(for episode: Episode) -> String {
    "\(episode.title) \(episode.description ?? "")"
  }

  private func sha256(_ text: String) -> String {
    let data = Data(text.utf8)
    let hash = SHA256.hash(data: data)
    let hashData = Data(hash)
    return
      hashData.map { byte in
        let hi = byte >> 4
        let lo = byte & 0x0F
        let hexChar = { (n: UInt8) -> Character in
          n < 10 ? Character(Unicode.Scalar(n + 48)) : Character(Unicode.Scalar(n + 87))
        }
        return String([hexChar(hi), hexChar(lo)])
      }
      .joined()
  }
}

// MARK: - Contextual Embedding Provider

struct ContextualEmbeddingProvider: Embedding, @unchecked Sendable {
  private let nlEmbedding: NLContextualEmbedding

  var revision: Int { nlEmbedding.revision }
  var maximumInputLength: Int { nlEmbedding.maximumSequenceLength }

  static func createIfAvailable() -> ContextualEmbeddingProvider? {
    guard let embedding = NLContextualEmbedding(language: .english),
      embedding.hasAvailableAssets
    else {
      return nil
    }
    do {
      try embedding.load()
      return ContextualEmbeddingProvider(nlEmbedding: embedding)
    } catch {
      return nil
    }
  }

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

// MARK: - Errors

enum EmbeddingError: Error {
  case modelUnavailable
  case noResult
}
