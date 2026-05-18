// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

// MARK: - EmbeddingService

enum EmbeddingService {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  // Bump when any recipe knob below changes. Folded into source hashes so
  // cached vectors invalidate on tuning, and read by RecommendationEngine
  // as a whitening-mean cache key — recipe bumps rewrite every vector in
  // place without changing count or model revision.
  static let recipeVersion = 2

  // Title weighs more than description to avoid boilerplate dominance.
  private static let titleWeight: Float = 0.6
  private static let descriptionWeight: Float = 0.4
  private static let podcastTitleWeight: Float = 0.6
  private static let podcastDescriptionWeight: Float = 0.4

  // Podcast vector blend ratio. Tuned low to preserve within-show
  // discrimination while still providing cross-show signal.
  private static let episodeBlendWeight: Float = 0.75
  private static let podcastBlendWeight: Float = 0.25

  // Regex<Substring> isn't Sendable upstream, but the compiled NFA is
  // immutable and matching is thread-safe. Precompile to avoid the
  // 2-per-episode recompile during the BG embedding pass.
  private nonisolated(unsafe) static let urlRegex = /https?:\/\/\S+/
  private nonisolated(unsafe) static let whitespaceRunRegex = /\s+/

  // Hydrating full Episode rows is ~125 MB for the full library; chunking
  // lets BG-task expiry preserve work already done instead of paying a
  // multi-second hydration pass up front.
  private static let hydrationChunkSize = 64

  // MARK: - Upsert Episode Embeddings

  static func upsertEpisodeEmbeddings(
    forIDs episodeIDs: [Episode.ID],
    embedding: ContextualEmbedding
  ) async throws {
    guard !episodeIDs.isEmpty else { return }
    let recommendationRepo = Container.shared.recommendationRepo()

    for start in stride(from: 0, to: episodeIDs.count, by: hydrationChunkSize) {
      try Task.checkCancellation()
      let end = min(start + hydrationChunkSize, episodeIDs.count)
      let chunk = Array(episodeIDs[start..<end])
      let episodes = try await recommendationRepo.episodes(for: chunk)
      try await upsertEpisodeEmbeddings(for: episodes, embedding: embedding)
    }
  }

  static func upsertEpisodeEmbeddings(
    for episodes: [Episode],
    embedding: ContextualEmbedding
  ) async throws {
    guard !episodes.isEmpty else { return }

    let recommendationRepo = Container.shared.recommendationRepo()

    let episodeIDs = episodes.map(\.id)
    let embeddingsByEpisodeID = try await recommendationRepo.embeddings(for: episodeIDs)

    let podcastIDs = Array(Set(episodes.map(\.podcastID)))
    let podcastsByID = try await recommendationRepo.podcasts(for: podcastIDs)
    let podcastEmbeddings = try await recommendationRepo.podcastEmbeddings(for: podcastIDs)

    var podcastVectorCache: [Podcast.ID: [Float]?] = [:]

    // One fsync per batch instead of one per episode.
    var pendingEpisodeEmbeddings = [UnsavedEpisodeEmbedding](capacity: episodes.count)
    var pendingPodcastEmbeddings = [UnsavedPodcastEmbedding](capacity: podcastIDs.count)

    // Embeddings whose source hash + revision still match but whose
    // contentUpdatedAt (episode or podcast) advanced past verificationDate.
    // Touching the date stops episodesNeedingEmbeddings from re-yielding them
    // without paying for a no-op vector recompute.
    var verifiedOnlyEpisodeIDs = [Episode.ID](capacity: episodes.count)
    let chunkStart = Date()

    var caughtCancellation: CancellationError?
    for episode in episodes {
      do {
        try Task.checkCancellation()
      } catch let error as CancellationError {
        caughtCancellation = error
        break
      }

      let existingEmbedding = embeddingsByEpisodeID[id: episode.id]
      let podcast = podcastsByID[id: episode.podcastID]
      let hash = fullSourceHash(for: episode, podcast: podcast)

      let needsRecompute =
        existingEmbedding == nil
        || existingEmbedding?.sourceHash != hash
        || existingEmbedding?.embeddingRevision != embedding.revision

      guard needsRecompute else {
        verifiedOnlyEpisodeIDs.append(episode.id)
        continue
      }

      // One bad episode mustn't abort the BG pass — it would re-enter
      // episodesNeedingEmbeddings forever. Cancellation breaks out of the
      // loop so the post-loop flush still runs.
      do {
        let podcastVector: [Float]?
        if let cached = podcastVectorCache[episode.podcastID] {
          podcastVector = cached
        } else {
          let resolved = try await resolvePodcastVector(
            podcast: podcast,
            embedding: embedding,
            cachedEmbedding: podcastEmbeddings[id: episode.podcastID]
          )
          podcastVector = resolved.vector
          if let fresh = resolved.fresh {
            pendingPodcastEmbeddings.append(fresh)
          }
          podcastVectorCache[episode.podcastID] = podcastVector
        }

        let unsavedEpisode = try await buildUnsavedEpisodeEmbedding(
          episode,
          hash: hash,
          embedding: embedding,
          podcastVector: podcastVector,
          verificationDate: chunkStart
        )
        pendingEpisodeEmbeddings.append(unsavedEpisode)
      } catch let error as CancellationError {
        caughtCancellation = error
        break
      } catch {
        Self.log.caughtError(
          "Failed to embed episode \(episode.toString); continuing batch",
          error
        )
      }
    }

    // Flush on cancellation too so earlier episodes in the chunk land
    // before the error propagates.
    try await recommendationRepo.upsertPodcastEmbeddings(pendingPodcastEmbeddings)
    try await recommendationRepo.upsertEmbeddings(pendingEpisodeEmbeddings)
    try await recommendationRepo.touchEmbeddingVerification(
      forEpisodeIDs: verifiedOnlyEpisodeIDs,
      at: chunkStart
    )

    if let caughtCancellation { throw caughtCancellation }
  }

  // MARK: - Unsaved Embedding

  // Mirrors the saved-side recipe so an unsaved row scores against the same
  // vector space.
  static func embeddingVector(
    for unsavedPodcastEpisode: UnsavedPodcastEpisode,
    embedding: ContextualEmbedding
  ) async throws -> [Float] {
    await embedding.loadAssetsIfAvailable()

    let unsavedPodcast = unsavedPodcastEpisode.unsavedPodcast
    let unsavedEpisode = unsavedPodcastEpisode.unsavedEpisode

    let cleanedPodcastTitle = cleanText(unsavedPodcast.title)
    let cleanedPodcastDescription = cleanText(unsavedPodcast.description)
    let podcastVector: [Float]? =
      cleanedPodcastTitle.isEmpty
      ? nil
      : try await computePodcastVector(
        cleanedTitle: cleanedPodcastTitle,
        cleanedDescription: cleanedPodcastDescription,
        embedding: embedding
      )

    return try await computeEpisodeEmbedding(
      cleanedTitle: cleanText(unsavedEpisode.title),
      cleanedDescription: cleanText(unsavedEpisode.description ?? ""),
      embedding: embedding,
      podcastVector: podcastVector
    )
  }

  // MARK: - Helpers

  // `fresh` is non-nil when a new row needs to be persisted; the caller
  // batches it with the chunk's pending writes.
  private static func resolvePodcastVector(
    podcast: Podcast?,
    embedding: ContextualEmbedding,
    cachedEmbedding: PodcastEmbedding?
  ) async throws -> (vector: [Float]?, fresh: UnsavedPodcastEmbedding?) {
    guard let podcast else { return (nil, nil) }

    let cleanedTitle = cleanText(podcast.title)
    let cleanedDescription = cleanText(podcast.description)
    guard !cleanedTitle.isEmpty else {
      Self.log.debug("Skipping podcast vector: empty title for podcast \(podcast.id)")
      return (nil, nil)
    }

    let hash = podcastSourceHash(
      cleanedTitle: cleanedTitle,
      cleanedDescription: cleanedDescription
    )

    if let cached = cachedEmbedding,
      cached.sourceHash == hash,
      cached.embeddingRevision == embedding.revision
    {
      return (cached.floatVector, nil)
    }

    let normalized = try await computePodcastVector(
      cleanedTitle: cleanedTitle,
      cleanedDescription: cleanedDescription,
      embedding: embedding
    )

    let fresh = UnsavedPodcastEmbedding(
      podcastId: podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: normalized),
      sourceHash: hash,
      embeddingRevision: embedding.revision,
      dimension: normalized.count
    )
    return (normalized, fresh)
  }

  private static func computePodcastVector(
    cleanedTitle: String,
    cleanedDescription: String,
    embedding: ContextualEmbedding
  ) async throws -> [Float] {
    let titleVector = try await embedding.vector(for: cleanedTitle)
    let descriptionText = cleanedDescription.isEmpty ? cleanedTitle : cleanedDescription
    let descriptionVector = try await embedding.vector(for: descriptionText)

    let blended = VectorMath.weightedAverage(
      titleVector,
      weight1: podcastTitleWeight,
      descriptionVector,
      weight2: podcastDescriptionWeight
    )
    return VectorMath.normalize(blended)
  }

  private static func buildUnsavedEpisodeEmbedding(
    _ episode: Episode,
    hash: String,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?,
    verificationDate: Date
  ) async throws -> UnsavedEpisodeEmbedding {
    let vector = try await computeEpisodeEmbedding(
      for: episode,
      embedding: embedding,
      podcastVector: podcastVector
    )

    return UnsavedEpisodeEmbedding(
      episodeId: episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: vector),
      sourceHash: hash,
      embeddingRevision: embedding.revision,
      dimension: vector.count,
      verificationDate: verificationDate
    )
  }

  private static func computeEpisodeEmbedding(
    for episode: Episode,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?
  ) async throws -> [Float] {
    try await computeEpisodeEmbedding(
      cleanedTitle: cleanText(episode.title),
      cleanedDescription: cleanText(episode.description ?? ""),
      embedding: embedding,
      podcastVector: podcastVector
    )
  }

  private static func computeEpisodeEmbedding(
    cleanedTitle: String,
    cleanedDescription: String,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?
  ) async throws -> [Float] {
    let titleVector = try await embedding.vector(for: cleanedTitle)
    let descriptionText = cleanedDescription.isEmpty ? cleanedTitle : cleanedDescription
    let descriptionVector = try await embedding.vector(for: descriptionText)

    var episodeVector = VectorMath.weightedAverage(
      titleVector,
      weight1: titleWeight,
      descriptionVector,
      weight2: descriptionWeight
    )

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
    // Decode entities first so e.g. `&lt;script&gt;` becomes `<script>` and
    // is then stripped by the tag pass.
    var result = text.decodingHTMLEntities().strippingHTMLTags()
    unsafe result.replace(urlRegex, with: "")
    unsafe result.replace(Timestamp.regex, with: "")
    unsafe result.replace(whitespaceRunRegex, with: " ")
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
