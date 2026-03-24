// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingService tests", .container)
class EmbeddingServiceTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.embeddingService) private var embeddingService
  @DynamicInjected(\.repo) private var repo

  // MARK: - Text Cleaning

  @Test("cleanText strips HTML tags")
  func cleanTextHTML() {
    let result = embeddingService.cleanText("<p>Hello <b>world</b></p>")
    #expect(result == "Hello world")
  }

  @Test("cleanText strips URLs")
  func cleanTextURLs() {
    let result = embeddingService.cleanText("Visit https://example.com for more")
    #expect(result == "Visit for more")
  }

  @Test("cleanText strips timestamps")
  func cleanTextTimestamps() {
    let result = embeddingService.cleanText("0:00 Intro 2:15 Main topic 1:02:15 Outro")
    #expect(result == "Intro Main topic Outro")
  }

  @Test("cleanText normalizes whitespace")
  func cleanTextWhitespace() {
    let result = embeddingService.cleanText("  too   many    spaces  ")
    #expect(result == "too many spaces")
  }

  // MARK: - Vector Math

  @Test("normalize produces unit vector")
  func normalizeUnit() {
    let vector: [Float] = [3.0, 4.0]
    let normalized = embeddingService.normalize(vector)
    let norm = sqrt(normalized.reduce(0) { $0 + $1 * $1 })
    #expect(abs(norm - 1.0) < 0.0001)
  }

  @Test("normalize handles zero vector gracefully")
  func normalizeZero() {
    let vector: [Float] = [0.0, 0.0, 0.0]
    let normalized = embeddingService.normalize(vector)
    #expect(normalized == [0.0, 0.0, 0.0])
  }

  @Test("dotProduct computes correctly")
  func dotProductCorrect() {
    let v1: [Float] = [1.0, 2.0, 3.0]
    let v2: [Float] = [4.0, 5.0, 6.0]
    let result = embeddingService.dotProduct(v1, v2)
    #expect(result == 32.0)
  }

  @Test("weightedAverage computes correctly")
  func weightedAverageCorrect() {
    let v1: [Float] = [1.0, 0.0]
    let v2: [Float] = [0.0, 1.0]
    let result = embeddingService.weightedAverage(v1, weight1: 0.6, v2, weight2: 0.4)
    #expect(abs(result[0] - 0.6) < 0.0001)
    #expect(abs(result[1] - 0.4) < 0.0001)
  }

  // MARK: - Embedding Caching

  @Test("ensureEmbeddings caches results and skips already computed")
  func ensureEmbeddingsCaching() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Test Episode",
      episodeDescription: "Test description"
    )
    let episode = podcastEpisode.episode

    let embedding = FakeEmbeddingProvider()

    // First call should compute and cache
    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: embedding,
      checkCancellation: false
    )

    let cached = try await repo.embedding(for: episode.id)
    #expect(cached != nil)
    #expect(cached?.dimension == 3)

    // Second call should skip (already cached)
    let originalComputedAt = cached!.creationDate
    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: embedding,
      checkCancellation: false
    )

    let cached2 = try await repo.embedding(for: episode.id)
    #expect(cached2?.creationDate == originalComputedAt)
  }

  // MARK: - Source Hash Invalidation

  @Test("stale sourceHash triggers recomputation")
  func sourceHashInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Test Title",
      episodeDescription: "Test description"
    )
    let episode = podcastEpisode.episode
    let embedding = FakeEmbeddingProvider()

    // First compute normally to get the correct hash
    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: embedding,
      checkCancellation: false
    )
    let correctHash = try await repo.embedding(for: episode.id)!.sourceHash
    let correctVector = try await repo.embedding(for: episode.id)!.floatVector

    // Overwrite with a stale hash but different vector
    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedEpisodeEmbedding(
      episodeId: episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: 1,
      dimension: 3
    )
    try await repo.upsertEmbedding(staleEmbedding)

    // Verify stale embedding was saved
    let afterStale = try await repo.embedding(for: episode.id)!
    #expect(afterStale.sourceHash == "stale-hash")

    // Recompute — should detect stale hash and recompute
    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: embedding,
      checkCancellation: false
    )

    let refreshed = try await repo.embedding(for: episode.id)!
    #expect(refreshed.sourceHash == correctHash)
    #expect(refreshed.floatVector == correctVector)
  }

  @Test("embedding revision changes trigger recomputation")
  func revisionInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "",
      episodeTitle: "Revision Test",
      episodeDescription: "Episode description"
    )
    let episode = podcastEpisode.episode
    let firstEmbedding = RevisionedEmbeddingProvider(revision: 1)
    let secondEmbedding = RevisionedEmbeddingProvider(revision: 2)

    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: firstEmbedding,
      checkCancellation: false
    )

    let cached = try #require(try await repo.embedding(for: episode.id))
    #expect(cached.embeddingRevision == 1)

    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: secondEmbedding,
      checkCancellation: false
    )

    let refreshed = try #require(try await repo.embedding(for: episode.id))
    #expect(refreshed.embeddingRevision == 2)
    #expect(refreshed.sourceHash == cached.sourceHash)
    #expect(refreshed.floatVector == cached.floatVector)
  }

  @Test("podcast description changes invalidate cached episode and podcast embeddings")
  func podcastDescriptionInvalidation() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Original podcast summary",
      episodeTitle: "Podcast Refresh",
      episodeDescription: "Episode description"
    )
    let embedding = FakeEmbeddingProvider()

    try await embeddingService.ensureEmbeddings(
      for: [podcastEpisode.episode],
      embedding: embedding,
      checkCancellation: false
    )

    let initialEpisodeEmbedding = try #require(
      try await repo.embedding(for: podcastEpisode.episode.id)
    )
    let initialPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )

    let updatedPodcast = try makeUnsavedPodcast(
      from: podcastEpisode.podcast,
      description: "Updated podcast summary"
    )
    let refreshedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: updatedPodcast,
        unsavedEpisode: try podcastEpisode.episode.toOriginalUnsavedEpisode()
      )
    )

    try await embeddingService.ensureEmbeddings(
      for: [refreshedPodcastEpisode.episode],
      embedding: embedding,
      checkCancellation: false
    )

    let refreshedEpisodeEmbedding = try #require(
      try await repo.embedding(for: refreshedPodcastEpisode.episode.id)
    )
    let refreshedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: refreshedPodcastEpisode.podcast.id)
    )

    #expect(refreshedEpisodeEmbedding.sourceHash != initialEpisodeEmbedding.sourceHash)
    #expect(refreshedEpisodeEmbedding.floatVector != initialEpisodeEmbedding.floatVector)
    #expect(refreshedPodcastEmbedding.sourceHash != initialPodcastEmbedding.sourceHash)
    #expect(refreshedPodcastEmbedding.floatVector != initialPodcastEmbedding.floatVector)
  }

  @Test("stale cached podcast embeddings are refreshed before reuse")
  func stalePodcastEmbeddingRefresh() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Podcast summary",
      episodeTitle: "Podcast Cache Refresh",
      episodeDescription: "Episode description"
    )
    let embedding = FakeEmbeddingProvider()

    let staleVector: [Float] = [99.0, 99.0, 99.0]
    let staleEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: embedding.revision,
      dimension: staleVector.count
    )
    try await repo.upsertPodcastEmbedding(staleEmbedding)

    let cachedBeforeRefresh = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    #expect(cachedBeforeRefresh.sourceHash == "stale-hash")

    _ = try await embeddingService.computeEmbedding(
      for: podcastEpisode.episode,
      embedding: embedding
    )

    let refreshedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    #expect(refreshedPodcastEmbedding.sourceHash != "stale-hash")
    #expect(refreshedPodcastEmbedding.embeddingRevision == embedding.revision)
    #expect(refreshedPodcastEmbedding.floatVector != cachedBeforeRefresh.floatVector)
  }

  @Test("embedding upserts replace existing rows instead of inserting duplicates")
  func embeddingUpsertsReplaceExistingRows() async throws {
    let podcastEpisode = try await makePodcastEpisode(
      podcastDescription: "Podcast summary",
      episodeTitle: "Upsert Coverage",
      episodeDescription: "Episode description"
    )

    let firstEpisodeEmbedding = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
      sourceHash: "episode-hash-1",
      embeddingRevision: 1,
      dimension: 3
    )
    let secondEpisodeEmbedding = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: [0.0, 1.0, 0.0]),
      sourceHash: "episode-hash-2",
      embeddingRevision: 2,
      dimension: 3
    )
    try await repo.upsertEmbedding(firstEpisodeEmbedding)
    try await repo.upsertEmbedding(secondEpisodeEmbedding)

    let firstPodcastEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: [0.0, 0.0, 1.0]),
      sourceHash: "podcast-hash-1",
      embeddingRevision: 1,
      dimension: 3
    )
    let secondPodcastEmbedding = UnsavedPodcastEmbedding(
      podcastId: podcastEpisode.podcast.id,
      vector: UnsavedPodcastEmbedding.vectorData(from: [0.5, 0.5, 0.5]),
      sourceHash: "podcast-hash-2",
      embeddingRevision: 2,
      dimension: 3
    )
    try await repo.upsertPodcastEmbedding(firstPodcastEmbedding)
    try await repo.upsertPodcastEmbedding(secondPodcastEmbedding)

    let savedEpisodeEmbedding = try #require(
      try await repo.embedding(for: podcastEpisode.episode.id)
    )
    let savedPodcastEmbedding = try #require(
      try await repo.podcastEmbedding(for: podcastEpisode.podcast.id)
    )
    let episodeRowCount = try #require(
      try await appDB.db.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
          arguments: [podcastEpisode.episode.id]
        )
      }
    )
    let podcastRowCount = try #require(
      try await appDB.db.read { db in
        try Int.fetchOne(
          db,
          sql: "SELECT COUNT(*) FROM podcastEmbedding WHERE podcastId = ?",
          arguments: [podcastEpisode.podcast.id]
        )
      }
    )

    #expect(savedEpisodeEmbedding.sourceHash == "episode-hash-2")
    #expect(savedEpisodeEmbedding.embeddingRevision == 2)
    #expect(savedPodcastEmbedding.sourceHash == "podcast-hash-2")
    #expect(savedPodcastEmbedding.embeddingRevision == 2)
    #expect(episodeRowCount == 1)
    #expect(podcastRowCount == 1)
  }

  // MARK: - Helpers

  private func makePodcastEpisode(
    podcastDescription: String,
    episodeTitle: String,
    episodeDescription: String
  ) async throws -> PodcastEpisode {
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(description: podcastDescription),
        unsavedEpisode: try Create.unsavedEpisode(
          title: episodeTitle,
          description: episodeDescription
        )
      )
    ])
    return try #require(podcastEpisodes.first)
  }

  private func makeUnsavedPodcast(
    from podcast: Podcast,
    description: String
  ) throws -> UnsavedPodcast {
    try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      iTunesID: podcast.iTunesID,
      title: podcast.title,
      image: podcast.image,
      description: description,
      link: podcast.link,
      lastUpdate: podcast.lastUpdate,
      subscriptionDate: podcast.subscriptionDate,
      defaultPlaybackRate: podcast.defaultPlaybackRate,
      queueAllEpisodes: podcast.queueAllEpisodes,
      cacheAllEpisodes: podcast.cacheAllEpisodes,
      notifyNewEpisodes: podcast.notifyNewEpisodes
    )
  }
}

private struct RevisionedEmbeddingProvider: Embedding, Sendable {
  let revision: Int
  let maximumInputLength: Int = 1000

  func vector(for text: String) throws -> [Float] {
    try FakeEmbeddingProvider().vector(for: text)
  }
}
