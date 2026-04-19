// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

// MARK: - EmbeddingService

enum EmbeddingService {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  // Title gets more weight than description to avoid boilerplate dominance
  private static let titleWeight: Float = 0.6
  private static let descriptionWeight: Float = 0.4

  // Podcast description blending ratio
  private static let episodeBlendWeight: Float = 0.6
  private static let podcastBlendWeight: Float = 0.4

  // Regex<Substring> isn't Sendable-annotated upstream, but its compiled NFA is
  // immutable and matching is thread-safe. Precompile once to avoid recompiling
  // on every cleanText call (called 2x per episode during BG embedding pass).
  private nonisolated(unsafe) static let htmlTagRegex = /<[^>]+>/
  private nonisolated(unsafe) static let urlRegex = /https?:\/\/\S+/
  private nonisolated(unsafe) static let whitespaceRunRegex = /\s+/

  // MARK: - Upsert Episode Embeddings

  static func upsertEpisodeEmbeddings(
    for episodes: [Episode],
    embedding: ContextualEmbedding
  ) async throws {
    guard !episodes.isEmpty else { return }

    let repo = Container.shared.repo()

    // Batch fetch all needed data upfront
    let episodeIDs = episodes.map(\.id)
    let embeddingsByEpisodeID = try await repo.embeddings(for: episodeIDs)

    let podcastIDs = Array(Set(episodes.map(\.podcastID)))
    let podcastsByID = try await repo.podcasts(for: podcastIDs)
    let podcastEmbeddings = try await repo.podcastEmbeddings(for: podcastIDs)

    // Cache computed podcast vectors to avoid redundant work within the batch
    var podcastVectorCache: [Podcast.ID: [Float]?] = [:]

    for episode in episodes {
      try Task.checkCancellation()

      let existingEmbedding = embeddingsByEpisodeID[id: episode.id]
      let podcast = podcastsByID[id: episode.podcastID]
      let hash = fullSourceHash(for: episode, podcast: podcast)

      let needsRecompute =
        existingEmbedding == nil
        || existingEmbedding?.sourceHash != hash
        || existingEmbedding?.embeddingRevision != embedding.revision

      guard needsRecompute else { continue }

      let podcastVector: [Float]?
      if let cached = podcastVectorCache[episode.podcastID] {
        podcastVector = cached
      } else {
        podcastVector = try await ensurePodcastEmbedding(
          podcast: podcast,
          embedding: embedding,
          cachedEmbedding: podcastEmbeddings[id: episode.podcastID]
        )
        podcastVectorCache[episode.podcastID] = podcastVector
      }

      try await upsertEpisodeEmbedding(
        episode,
        hash: hash,
        embedding: embedding,
        podcastVector: podcastVector
      )
    }
  }

  // MARK: - Helpers

  private static func ensurePodcastEmbedding(
    podcast: Podcast?,
    embedding: ContextualEmbedding,
    cachedEmbedding: PodcastEmbedding?
  ) async throws -> [Float]? {
    guard let podcast else { return nil }

    let cleanedDescription = cleanText(podcast.description)
    guard !cleanedDescription.isEmpty else { return nil }

    let hash = cleanedDescription.sha256()

    // Return cached if still fresh (same source hash and revision)
    if let cached = cachedEmbedding,
      cached.sourceHash == hash,
      cached.embeddingRevision == embedding.revision
    {
      return cached.floatVector
    }

    let vector = try embedding.vector(for: cleanedDescription)
    let normalized = VectorMath.normalize(vector)

    let unsaved = UnsavedPodcastEmbedding(
      podcastId: podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: normalized),
      sourceHash: hash,
      embeddingRevision: embedding.revision,
      dimension: normalized.count
    )
    try await Container.shared.repo().upsertPodcastEmbedding(unsaved)

    return normalized
  }

  private static func upsertEpisodeEmbedding(
    _ episode: Episode,
    hash: String,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?
  ) async throws {
    let vector = try computeEpisodeEmbedding(
      for: episode,
      embedding: embedding,
      podcastVector: podcastVector
    )

    let unsaved = UnsavedEpisodeEmbedding(
      episodeId: episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: vector),
      sourceHash: hash,
      embeddingRevision: embedding.revision,
      dimension: vector.count
    )
    try await Container.shared.repo().upsertEmbedding(unsaved)
  }

  private static func computeEpisodeEmbedding(
    for episode: Episode,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?
  ) throws -> [Float] {
    let cleanedTitle = cleanText(episode.title)
    let cleanedDescription = cleanText(episode.description ?? "")

    let titleVector = try embedding.vector(for: cleanedTitle)

    let descriptionText = cleanedDescription.isEmpty ? cleanedTitle : cleanedDescription
    let descriptionVector = try embedding.vector(for: descriptionText)

    // Weighted average of title and description
    var episodeVector = VectorMath.weightedAverage(
      titleVector,
      weight1: titleWeight,
      descriptionVector,
      weight2: descriptionWeight
    )

    // Blend with podcast description embedding
    if let podcastVector {
      episodeVector = VectorMath.weightedAverage(
        episodeVector,
        weight1: episodeBlendWeight,
        podcastVector,
        weight2: podcastBlendWeight
      )
    }

    return VectorMath.normalize(episodeVector)
  }

  private static func fullSourceHash(for episode: Episode, podcast: Podcast?) -> String {
    var text = "\(episode.title) \(episode.description ?? "")"
    if let podcast {
      text += " \(podcast.description)"
    }
    return text.sha256()
  }

  static func cleanText(_ text: String) -> String {
    var result = text
    unsafe result.replace(htmlTagRegex, with: " ")
    unsafe result.replace(urlRegex, with: "")
    result.replace(Timestamp.regex, with: "")
    unsafe result.replace(whitespaceRunRegex, with: " ")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
