// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

// MARK: - EmbeddingService

enum EmbeddingService {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  // Bump when any recipe knob below changes (weights, blend, cleanText rules).
  // Folded into source hashes so cached vectors invalidate on tuning.
  private static let recipeVersion = 2

  // Title gets more weight than description to avoid boilerplate dominance
  private static let titleWeight: Float = 0.6
  private static let descriptionWeight: Float = 0.4

  // Podcast vector recipe mirrors the episode recipe. Title carries show
  // identity (important when descriptions are generic or missing); description
  // adds topical context when available.
  private static let podcastTitleWeight: Float = 0.6
  private static let podcastDescriptionWeight: Float = 0.4

  // Podcast description blending ratio. Tuned lower to preserve within-show
  // discrimination while still providing cross-show semantic signal.
  private static let episodeBlendWeight: Float = 0.75
  private static let podcastBlendWeight: Float = 0.25

  // Regex<Substring> isn't Sendable-annotated upstream, but its compiled NFA is
  // immutable and matching is thread-safe. Precompile once to avoid recompiling
  // on every cleanText call (called 2x per episode during BG embedding pass).
  private nonisolated(unsafe) static let urlRegex = /https?:\/\/\S+/
  private nonisolated(unsafe) static let whitespaceRunRegex = /\s+/

  // Chunk size for the ID-driven entry point. Hydrating full Episode rows is
  // ~125 MB for the full library; chunking lets BG-task expiry preserve work
  // already done instead of paying a multi-second hydration pass up front.
  private static let hydrationChunkSize = 64

  // MARK: - Upsert Episode Embeddings

  static func upsertEpisodeEmbeddings(
    forIDs episodeIDs: [Episode.ID],
    embedding: ContextualEmbedding
  ) async throws {
    guard !episodeIDs.isEmpty else { return }
    let repo = Container.shared.repo()

    for start in stride(from: 0, to: episodeIDs.count, by: hydrationChunkSize) {
      try Task.checkCancellation()
      let end = min(start + hydrationChunkSize, episodeIDs.count)
      let chunk = Array(episodeIDs[start..<end])
      let episodes = try await repo.episodes(for: chunk)
      try await upsertEpisodeEmbeddings(for: episodes, embedding: embedding)
    }
  }

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

      // One bad episode (unexpected throw from the embedding model, a transient
      // DB error, etc.) must not abort the whole BG pass — otherwise the same
      // episode re-enters episodesNeedingEmbeddings on the next run and we
      // loop forever on it. Cancellation still propagates.
      do {
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
      } catch {
        if error is CancellationError { throw error }
        Self.log.caughtError(
          "Failed to embed episode \(episode.toString); continuing batch",
          error
        )
      }
    }
  }

  // MARK: - Helpers

  private static func ensurePodcastEmbedding(
    podcast: Podcast?,
    embedding: ContextualEmbedding,
    cachedEmbedding: PodcastEmbedding?
  ) async throws -> [Float]? {
    guard let podcast else { return nil }

    let cleanedTitle = cleanText(podcast.title)
    let cleanedDescription = cleanText(podcast.description)
    guard !cleanedTitle.isEmpty else {
      Self.log.debug("Skipping podcast vector: empty title for podcast \(podcast.id)")
      return nil
    }

    let hash = podcastSourceHash(
      cleanedTitle: cleanedTitle,
      cleanedDescription: cleanedDescription
    )

    // Return cached if still fresh (same source hash and revision)
    if let cached = cachedEmbedding,
      cached.sourceHash == hash,
      cached.embeddingRevision == embedding.revision
    {
      return cached.floatVector
    }

    let titleVector = try embedding.vector(for: cleanedTitle)
    let descriptionText = cleanedDescription.isEmpty ? cleanedTitle : cleanedDescription
    let descriptionVector = try embedding.vector(for: descriptionText)

    let blended = VectorMath.weightedAverage(
      titleVector,
      weight1: podcastTitleWeight,
      descriptionVector,
      weight2: podcastDescriptionWeight
    )
    let normalized = VectorMath.normalize(blended)

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
    let cleanedTitle = cleanText(episode.title)
    let cleanedDescription = cleanText(episode.description ?? "")
    let cleanedPodcastTitle: String
    let cleanedPodcastDescription: String
    if let podcast {
      cleanedPodcastTitle = cleanText(podcast.title)
      cleanedPodcastDescription = cleanText(podcast.description)
    } else {
      cleanedPodcastTitle = ""
      cleanedPodcastDescription = ""
    }
    let components = [
      "r\(recipeVersion)",
      cleanedTitle,
      cleanedDescription,
      cleanedPodcastTitle,
      cleanedPodcastDescription,
    ]
    return components.joined(separator: "\u{1F}").sha256()
  }

  private static func podcastSourceHash(
    cleanedTitle: String,
    cleanedDescription: String
  ) -> String {
    let components = [
      "r\(recipeVersion)",
      cleanedTitle,
      cleanedDescription,
    ]
    return components.joined(separator: "\u{1F}").sha256()
  }

  static func cleanText(_ text: String) -> String {
    // Decode entities first so `&lt;script&gt;` becomes `<script>` and is then
    // stripped by the tag pass.
    var result = text.decodingHTMLEntities().strippingHTMLTags()
    unsafe result.replace(urlRegex, with: "")
    unsafe result.replace(Timestamp.regex, with: "")
    unsafe result.replace(whitespaceRunRegex, with: " ")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
