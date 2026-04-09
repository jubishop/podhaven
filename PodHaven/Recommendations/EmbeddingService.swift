// Copyright Justin Bishop, 2026

import CryptoKit
import FactoryKit
import Foundation
import Logging
import NaturalLanguage

// MARK: - Container

extension Container {
  var embeddingService: Factory<EmbeddingService> {
    Factory(self) { EmbeddingService() }.scope(.cached)
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

  func computeEmbedding(for episode: Episode, embedding: any Embeddable) async throws -> [Float] {
    let cleanedTitle = cleanText(episode.title)
    let cleanedDescription = cleanText(episode.description ?? "")

    let titleVector = try embedding.vector(for: cleanedTitle)

    let descriptionText =
      cleanedDescription.isEmpty
      ? cleanedTitle
      : String(cleanedDescription.prefix(embedding.maximumInputLength))
    let descriptionVector = try embedding.vector(for: descriptionText)

    // Weighted average of title and description
    var episodeVector = VectorMath.weightedAverage(
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
      episodeVector = VectorMath.weightedAverage(
        episodeVector,
        weight1: Self.episodeBlendWeight,
        podcastVector,
        weight2: Self.podcastBlendWeight
      )
    }

    return VectorMath.normalize(episodeVector)
  }

  // MARK: - Podcast Embedding

  private func fetchOrComputePodcastEmbedding(
    podcastID: Podcast.ID,
    embedding: any Embeddable
  ) async throws -> [Float]? {
    guard let podcast = try await repo.podcast(podcastID) else { return nil }

    let cleanedDescription = cleanText(podcast.description)
    guard !cleanedDescription.isEmpty else { return nil }

    let hash = sha256(cleanedDescription)

    // Return cached if still fresh (same source hash and revision)
    if let cached = try await repo.podcastEmbedding(for: podcastID),
      cached.sourceHash == hash,
      cached.embeddingRevision == embedding.revision
    {
      return cached.floatVector
    }

    let text = String(cleanedDescription.prefix(embedding.maximumInputLength))
    let vector = try embedding.vector(for: text)
    let normalized = VectorMath.normalize(vector)

    let unsaved = UnsavedPodcastEmbedding(
      podcastId: podcastID,
      vector: UnsavedPodcastEmbedding.vectorData(from: normalized),
      sourceHash: hash,
      embeddingRevision: embedding.revision,
      dimension: normalized.count
    )
    try await repo.upsertPodcastEmbedding(unsaved)

    return normalized
  }

  // MARK: - Ensure Embeddings

  func ensureEmbeddings(
    for episodes: [Episode],
    embedding: any Embeddable,
    checkCancellation: Bool = true
  ) async throws {
    for episode in episodes {
      if checkCancellation { try Task.checkCancellation() }

      let existingEmbedding = try await repo.embedding(for: episode.id)
      let hash = try await fullSourceHash(for: episode)

      let needsRecompute =
        existingEmbedding == nil
        || existingEmbedding?.sourceHash != hash
        || existingEmbedding?.embeddingRevision != embedding.revision

      guard needsRecompute else { continue }

      let vector = try await computeEmbedding(for: episode, embedding: embedding)

      let unsaved = UnsavedEpisodeEmbedding(
        episodeId: episode.id,
        vector: UnsavedEpisodeEmbedding.vectorData(from: vector),
        sourceHash: hash,
        embeddingRevision: embedding.revision,
        dimension: vector.count
      )
      try await repo.upsertEmbedding(unsaved)
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

  // MARK: - Helpers

  // Includes episode text AND podcast description so the hash invalidates
  // when either the episode or its podcast description changes.
  private func fullSourceHash(for episode: Episode) async throws -> String {
    var text = "\(episode.title) \(episode.description ?? "")"
    if let podcast = try await repo.podcast(episode.podcastID) {
      text += " \(podcast.description)"
    }
    return sha256(text)
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
