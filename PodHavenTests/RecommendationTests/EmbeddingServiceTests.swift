// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingService tests", .container)
class EmbeddingServiceTests {
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
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      title: "Test Episode",
      description: "Test description"
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
    ])
    let episode = podcastEpisodes.first!.episode

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
    let originalComputedAt = cached!.computedAt
    try await embeddingService.ensureEmbeddings(
      for: [episode],
      embedding: embedding,
      checkCancellation: false
    )

    let cached2 = try await repo.embedding(for: episode.id)
    #expect(cached2?.computedAt == originalComputedAt)
  }

  // MARK: - Source Hash Invalidation

  @Test(
    "stale sourceHash triggers recomputation",
    .disabled("Investigate podcast blending interaction in test environment")
  )
  func sourceHashInvalidation() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      title: "Test Title",
      description: "Test description"
    )
    let podcastEpisodes = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
    ])
    let episode = podcastEpisodes.first!.episode
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
    let staleEmbedding = EpisodeEmbedding(
      episodeId: episode.id,
      vector: EpisodeEmbedding.vectorData(from: staleVector),
      sourceHash: "stale-hash",
      embeddingRevision: 1,
      dimension: 3,
      computedAt: Date()
    )
    try await repo.insertEmbedding(staleEmbedding)

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
}
