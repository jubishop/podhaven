// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// Numerical correctness tests for `RecommendationRepo.whiteningTransform`. The
// single-pass `Cov = E[xxᵀ] - μμᵀ` reformulation is the most fragile piece of
// the recommendation efficiency rewrite — these lock in the math against a
// handcrafted corpus where the expected mean and dominant direction are known
// by construction.
@Suite("Whitening repo tests", .container)
class WhiteningRepoTests {
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.repo) private var repo

  private func seedEmbedding(_ vector: [Float]) async throws {
    let podcastEpisode = try await repo
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(
          unsavedPodcast: try Create.unsavedPodcast(),
          unsavedEpisode: try Create.unsavedEpisode()
        )
      ])
      .first!
    let unsaved = UnsavedEpisodeEmbedding(
      episodeId: podcastEpisode.episode.id,
      vector: UnsavedEpisodeEmbedding.vectorData(from: vector),
      sourceHash: "hash-\(UUID().uuidString)",
      embeddingRevision: 1,
      dimension: vector.count,
      verificationDate: Date()
    )
    try await recommendationRepo.upsertEmbeddings([unsaved])
  }

  @Test("mean-only transform computes corpus mean")
  func meanOnlyComputesAverage() async throws {
    try await seedEmbedding([1, 0, 0])
    try await seedEmbedding([0, 1, 0])
    try await seedEmbedding([0, 0, 1])

    let transform = try #require(
      await recommendationRepo.whiteningTransform(principalComponentCount: 0)
    )
    let expected: [Float] = [1.0 / 3, 1.0 / 3, 1.0 / 3]
    for (i, x) in transform.mean.enumerated() {
      #expect(abs(x - expected[i]) < 0.0001)
    }
    #expect(transform.principalComponents.isEmpty)
  }

  @Test("k=1 recovers the dominant variance direction")
  func topPCMatchesEngineeredVariance() async throws {
    // Construct a corpus with high variance along the x-axis (alternating
    // +/-1) and zero variance elsewhere. The dominant PC must be ±[1, 0, 0].
    for _ in 0..<8 {
      try await seedEmbedding([1, 0, 0])
      try await seedEmbedding([-1, 0, 0])
    }

    let transform = try #require(
      await recommendationRepo.whiteningTransform(principalComponentCount: 1)
    )
    #expect(transform.principalComponents.count == 1)
    let pc = transform.principalComponents[0]
    #expect(abs(abs(pc[0]) - 1.0) < 0.01)
    #expect(abs(pc[1]) < 0.01)
    #expect(abs(pc[2]) < 0.01)
  }

  @Test("empty corpus returns nil")
  func emptyCorpusReturnsNil() async throws {
    let transform = try await recommendationRepo.whiteningTransform(
      principalComponentCount: 0
    )
    #expect(transform == nil)
  }
}
