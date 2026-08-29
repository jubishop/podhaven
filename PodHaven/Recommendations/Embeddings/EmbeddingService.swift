// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import IdentifiedCollections
import Logging

// MARK: - EmbeddingService

struct EmbeddingBatchResult: Equatable, Sendable {
  let failedEpisodeCount: Int
}

enum EmbeddingService {
  private static let log = Log.as(LogSubsystem.Recommendations.embedding)

  private struct CleanedEmbeddingText: Sendable {
    let title: String
    let description: String
  }

  private struct BatchMetrics: Sendable {
    var episodeCount = 0
    var podcastIDs: Set<Podcast.ID> = []
    var cleanInputCount = 0
    var inputByteCount = 0
    var maximumInputByteCount = 0
    var cleaningDuration: Duration = .zero
    var hashingDuration: Duration = .zero
    var embeddingDuration: Duration = .zero
    var databaseDuration: Duration = .zero

    mutating func recordCleanInput(_ text: String) {
      let byteCount = text.utf8.count
      cleanInputCount += 1
      inputByteCount += byteCount
      maximumInputByteCount = max(maximumInputByteCount, byteCount)
    }
  }

  private struct BatchState: Sendable {
    var metrics = BatchMetrics()
    var cleanedPodcasts: [Podcast.ID: CleanedEmbeddingText] = [:]
    var podcastVectors: [Podcast.ID: [Float]?] = [:]
  }

  private struct ChunkResult: Sendable {
    let failedEpisodeCount: Int
    let state: BatchState
    let cancellation: CancellationError?
  }

  private enum BatchOutcome: String, Sendable {
    case completed
    case cancelled
    case failed

    var event: String {
      switch self {
      case .completed:
        "batchCompleted"
      case .cancelled:
        "batchCancelled"
      case .failed:
        "batchFailed"
      }
    }
  }

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
  private static let slowBatchThreshold: Duration = .seconds(10)

  // MARK: - Upsert Episode Embeddings

  @discardableResult static func upsertEpisodeEmbeddings(
    forIDs episodeIDs: [Episode.ID],
    embedding: ContextualEmbedding
  ) async throws -> EmbeddingBatchResult {
    guard !episodeIDs.isEmpty else { return EmbeddingBatchResult(failedEpisodeCount: 0) }
    let recommendationRepo = Container.shared.recommendationRepo()
    let clockNow = Container.shared.continuousClockNow()
    let startedAt = clockNow()
    var failedEpisodeCount = 0
    var state = BatchState()

    do {
      for start in stride(from: 0, to: episodeIDs.count, by: hydrationChunkSize) {
        try Task.checkCancellation()
        let end = min(start + hydrationChunkSize, episodeIDs.count)
        let chunk = Array(episodeIDs[start..<end])
        let verificationDate = Date()
        let databaseStartedAt = clockNow()
        let episodes = try await recommendationRepo.episodes(for: chunk)
        state.metrics.databaseDuration += clockNow() - databaseStartedAt
        let result = try await upsertEpisodeEmbeddings(
          for: episodes,
          embedding: embedding,
          verificationDate: verificationDate,
          state: state,
          clockNow: clockNow
        )
        state = result.state
        failedEpisodeCount += result.failedEpisodeCount
        if let cancellation = result.cancellation {
          throw cancellation
        }
      }
    } catch let error as CancellationError {
      logBatchTelemetry(
        outcome: .cancelled,
        state: state,
        failedEpisodeCount: failedEpisodeCount,
        wallDuration: clockNow() - startedAt
      )
      throw error
    } catch {
      Self.log.caughtError(
        batchTelemetryMessage(
          outcome: .failed,
          state: state,
          failedEpisodeCount: failedEpisodeCount,
          wallDuration: clockNow() - startedAt
        ),
        error
      )
      throw error
    }

    logBatchTelemetry(
      outcome: .completed,
      state: state,
      failedEpisodeCount: failedEpisodeCount,
      wallDuration: clockNow() - startedAt
    )
    return EmbeddingBatchResult(failedEpisodeCount: failedEpisodeCount)
  }

  @discardableResult static func upsertEpisodeEmbeddings(
    for episodes: [Episode],
    embedding: ContextualEmbedding
  ) async throws -> EmbeddingBatchResult {
    guard !episodes.isEmpty else { return EmbeddingBatchResult(failedEpisodeCount: 0) }
    let clockNow = Container.shared.continuousClockNow()
    let startedAt = clockNow()
    var state = BatchState()
    var failedEpisodeCount = 0

    do {
      let result = try await upsertEpisodeEmbeddings(
        for: episodes,
        embedding: embedding,
        verificationDate: Date(),
        state: state,
        clockNow: clockNow
      )
      state = result.state
      failedEpisodeCount = result.failedEpisodeCount
      let wallDuration = clockNow() - startedAt
      if let cancellation = result.cancellation {
        throw cancellation
      }
      logBatchTelemetry(
        outcome: .completed,
        state: state,
        failedEpisodeCount: failedEpisodeCount,
        wallDuration: wallDuration
      )
      return EmbeddingBatchResult(failedEpisodeCount: failedEpisodeCount)
    } catch let error as CancellationError {
      logBatchTelemetry(
        outcome: .cancelled,
        state: state,
        failedEpisodeCount: failedEpisodeCount,
        wallDuration: clockNow() - startedAt
      )
      throw error
    } catch {
      Self.log.caughtError(
        batchTelemetryMessage(
          outcome: .failed,
          state: state,
          failedEpisodeCount: failedEpisodeCount,
          wallDuration: clockNow() - startedAt
        ),
        error
      )
      throw error
    }
  }

  private static func upsertEpisodeEmbeddings(
    for episodes: [Episode],
    embedding: ContextualEmbedding,
    verificationDate: Date,
    state initialState: BatchState,
    clockNow: @Sendable () -> ContinuousClock.Instant
  ) async throws -> ChunkResult {
    guard !episodes.isEmpty else {
      return ChunkResult(
        failedEpisodeCount: 0,
        state: initialState,
        cancellation: nil
      )
    }

    let recommendationRepo = Container.shared.recommendationRepo()
    var state = initialState
    state.metrics.episodeCount += episodes.count
    state.metrics.podcastIDs.formUnion(episodes.map(\.podcastID))

    let databaseStartedAt = clockNow()
    let episodeIDs = episodes.map(\.id)
    let embeddingsByEpisodeID = try await recommendationRepo.embeddings(for: episodeIDs)

    let podcastIDs = Array(Set(episodes.map(\.podcastID)))
    let podcastsByID = try await recommendationRepo.podcasts(for: podcastIDs)
    let podcastEmbeddings = try await recommendationRepo.podcastEmbeddings(for: podcastIDs)
    state.metrics.databaseDuration += clockNow() - databaseStartedAt

    // One fsync per batch instead of one per episode.
    var pendingEpisodeEmbeddings = [UnsavedEpisodeEmbedding](capacity: episodes.count)
    var pendingPodcastEmbeddings = [UnsavedPodcastEmbedding](capacity: podcastIDs.count)

    // Embeddings whose source hash + revision still match but whose
    // contentUpdatedAt (episode or podcast) advanced past verificationDate.
    // Touching the date stops episodesNeedingEmbeddings from re-yielding them
    // without paying for a no-op vector recompute.
    var verifiedOnlyEpisodeIDs = [Episode.ID](capacity: episodes.count)

    var caughtCancellation: CancellationError?
    var failedEpisodeCount = 0
    var failedEpisodeIDs: [Episode.ID] = []
    var succeededEpisodeIDs: [Episode.ID] = []
    for episode in episodes {
      do {
        try Task.checkCancellation()
      } catch let error as CancellationError {
        caughtCancellation = error
        break
      }

      let existingEmbedding = embeddingsByEpisodeID[id: episode.id]
      let podcast = podcastsByID[id: episode.podcastID]
      let cleaningStartedAt = clockNow()
      let cleanedEpisode = CleanedEmbeddingText(
        title: cleanText(episode.title),
        description: cleanText(episode.description ?? "")
      )
      state.metrics.recordCleanInput(episode.title)
      state.metrics.recordCleanInput(episode.description ?? "")

      let cleanedPodcast: CleanedEmbeddingText?
      if let cached = state.cleanedPodcasts[episode.podcastID] {
        cleanedPodcast = cached
      } else if let podcast {
        let cleaned = CleanedEmbeddingText(
          title: cleanText(podcast.title),
          description: cleanText(podcast.description)
        )
        state.metrics.recordCleanInput(podcast.title)
        state.metrics.recordCleanInput(podcast.description)
        state.cleanedPodcasts[episode.podcastID] = cleaned
        cleanedPodcast = cleaned
      } else {
        cleanedPodcast = nil
      }
      state.metrics.cleaningDuration += clockNow() - cleaningStartedAt

      let hashingStartedAt = clockNow()
      let hash = fullSourceHash(
        cleanedEpisode: cleanedEpisode,
        cleanedPodcast: cleanedPodcast
      )
      state.metrics.hashingDuration += clockNow() - hashingStartedAt

      let needsRecompute =
        existingEmbedding == nil
        || existingEmbedding?.sourceHash != hash
        || existingEmbedding?.embeddingRevision != embedding.revision

      guard needsRecompute else {
        verifiedOnlyEpisodeIDs.append(episode.id)
        succeededEpisodeIDs.append(episode.id)
        continue
      }

      // One bad episode mustn't abort the BG pass. Cancellation breaks out of
      // the loop so the post-loop flush still runs.
      do {
        let embeddingStartedAt = clockNow()
        defer {
          state.metrics.embeddingDuration += clockNow() - embeddingStartedAt
        }
        let podcastVector: [Float]?
        if let cached = state.podcastVectors[episode.podcastID] {
          podcastVector = cached
        } else {
          let resolved = try await resolvePodcastVector(
            podcast: podcast,
            cleanedPodcast: cleanedPodcast,
            embedding: embedding,
            cachedEmbedding: podcastEmbeddings[id: episode.podcastID]
          )
          podcastVector = resolved.vector
          if let fresh = resolved.fresh {
            pendingPodcastEmbeddings.append(fresh)
          }
          state.podcastVectors[episode.podcastID] = podcastVector
        }

        let unsavedEpisode = try await buildUnsavedEpisodeEmbedding(
          episode,
          cleanedEpisode: cleanedEpisode,
          hash: hash,
          embedding: embedding,
          podcastVector: podcastVector,
          verificationDate: verificationDate
        )
        pendingEpisodeEmbeddings.append(unsavedEpisode)
        succeededEpisodeIDs.append(episode.id)
      } catch let error as CancellationError {
        caughtCancellation = error
        break
      } catch {
        failedEpisodeCount += 1
        failedEpisodeIDs.append(episode.id)
        Self.log.caughtError(
          "Failed to embed episode \(episode.toString); continuing batch",
          error,
          level: .notice
        )
      }
    }

    // Flush on cancellation too so earlier episodes in the chunk land
    // before the error propagates.
    let writeStartedAt = clockNow()
    try await recommendationRepo.upsertPodcastEmbeddings(pendingPodcastEmbeddings)
    try await recommendationRepo.upsertEmbeddings(pendingEpisodeEmbeddings)
    try await recommendationRepo.touchEmbeddingVerification(
      forEpisodeIDs: verifiedOnlyEpisodeIDs,
      at: verificationDate
    )
    let newlyQuarantinedCount = try await recommendationRepo.updateEmbeddingFailureState(
      failedEpisodeIDs: failedEpisodeIDs,
      succeededEpisodeIDs: succeededEpisodeIDs,
      pipelineVersion: EmbeddingPipelineVersion(
        embeddingRevision: embedding.revision,
        recipeVersion: recipeVersion
      )
    )
    state.metrics.databaseDuration += clockNow() - writeStartedAt
    if newlyQuarantinedCount > 0 {
      Self.log.notice(
        "Quarantined \(newlyQuarantinedCount) episode embedding failures after repeated attempts"
      )
    }

    return ChunkResult(
      failedEpisodeCount: failedEpisodeCount,
      state: state,
      cancellation: caughtCancellation
    )
  }

  // MARK: - Unsaved Embedding

  // Mirrors the saved-side recipe so an unsaved row scores against the same
  // vector space.
  //
  // The podcast-context vector is identical for every episode of a feed, so a
  // batch caller computes it once and threads it through episodeEmbeddingVector
  // instead of re-embedding the podcast title/description per episode.
  @concurrent static func podcastContextVector(
    for unsavedPodcast: UnsavedPodcast,
    embedding: ContextualEmbedding
  ) async throws -> [Float]? {
    await embedding.loadAssetsIfAvailable()
    let cleanedTitle = cleanText(unsavedPodcast.title)
    guard !cleanedTitle.isEmpty else { return nil }
    return try await computePodcastVector(
      cleanedTitle: cleanedTitle,
      cleanedDescription: cleanText(unsavedPodcast.description),
      embedding: embedding
    )
  }

  @concurrent static func episodeEmbeddingVector(
    for unsavedEpisode: UnsavedEpisode,
    podcastVector: [Float]?,
    embedding: ContextualEmbedding
  ) async throws -> [Float] {
    try await computeEpisodeEmbedding(
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
    cleanedPodcast: CleanedEmbeddingText?,
    embedding: ContextualEmbedding,
    cachedEmbedding: PodcastEmbedding?
  ) async throws -> (vector: [Float]?, fresh: UnsavedPodcastEmbedding?) {
    guard let podcast, let cleanedPodcast else { return (nil, nil) }

    guard !cleanedPodcast.title.isEmpty else {
      Self.log.debug("Skipping podcast vector: empty title for podcast \(podcast.id)")
      return (nil, nil)
    }

    let hash = podcastSourceHash(
      cleanedTitle: cleanedPodcast.title,
      cleanedDescription: cleanedPodcast.description
    )

    if let cached = cachedEmbedding,
      cached.sourceHash == hash,
      cached.embeddingRevision == embedding.revision
    {
      return (cached.floatVector, nil)
    }

    let normalized = try await computePodcastVector(
      cleanedTitle: cleanedPodcast.title,
      cleanedDescription: cleanedPodcast.description,
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
    cleanedEpisode: CleanedEmbeddingText,
    hash: String,
    embedding: ContextualEmbedding,
    podcastVector: [Float]?,
    verificationDate: Date
  ) async throws -> UnsavedEpisodeEmbedding {
    let vector = try await computeEpisodeEmbedding(
      cleanedTitle: cleanedEpisode.title,
      cleanedDescription: cleanedEpisode.description,
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

  private static func fullSourceHash(
    cleanedEpisode: CleanedEmbeddingText,
    cleanedPodcast: CleanedEmbeddingText?
  ) -> String {
    let components = [
      "r\(recipeVersion)",
      cleanedEpisode.title,
      cleanedEpisode.description,
      cleanedPodcast?.title ?? "",
      cleanedPodcast?.description ?? "",
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

  private static func logBatchTelemetry(
    outcome: BatchOutcome,
    state: BatchState,
    failedEpisodeCount: Int,
    wallDuration: Duration
  ) {
    let message = batchTelemetryMessage(
      outcome: outcome,
      state: state,
      failedEpisodeCount: failedEpisodeCount,
      wallDuration: wallDuration
    )
    if wallDuration >= slowBatchThreshold {
      Self.log.warning("\(message)")
    } else {
      Self.log.info("\(message)")
    }
  }

  private static func batchTelemetryMessage(
    outcome: BatchOutcome,
    state: BatchState,
    failedEpisodeCount: Int,
    wallDuration: Duration
  ) -> String {
    let metrics = state.metrics
    return """
      embeddingTelemetry event=\(outcome.event) outcome=\(outcome.rawValue) \
      episodes=\(metrics.episodeCount) uniquePodcasts=\(metrics.podcastIDs.count) \
      failedEpisodes=\(failedEpisodeCount) cleanInputs=\(metrics.cleanInputCount) \
      inputBytes=\(metrics.inputByteCount) maxInputBytes=\(metrics.maximumInputByteCount) \
      cleaningSeconds=\(metrics.cleaningDuration.asTimeInterval) \
      hashingSeconds=\(metrics.hashingDuration.asTimeInterval) \
      embeddingSeconds=\(metrics.embeddingDuration.asTimeInterval) \
      databaseSeconds=\(metrics.databaseDuration.asTimeInterval) \
      wallSeconds=\(wallDuration.asTimeInterval)
      """
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
