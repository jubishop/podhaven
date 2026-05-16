// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of ListablePodcastEpisode tests", .container)
class ListablePodcastEpisodeTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private func fetchListablePodcastEpisode(
    _ episodeID: Episode.ID
  ) async throws -> ListablePodcastEpisode {
    let listables =
      try await observatory.listablePodcastEpisodes(
        filter: Episode.Columns.id == episodeID
      )
      .get()
    return try #require(listables.first)
  }

  // MARK: - hasEmbedding

  @Test("hasEmbedding is false when no embedding row exists for the episode")
  func hasEmbeddingFalseWithoutEmbedding() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Unprocessed Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "no-embedding",
          title: "No Embedding Yet"
        )
      )
    )

    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)

    #expect(listable.hasEmbedding == false)
  }

  @Test("hasEmbedding is true after an embedding row is inserted for the episode")
  func hasEmbeddingTrueAfterInsert() async throws {
    let podcastEpisode = try await Create.podcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: try Create.unsavedPodcast(title: "Processed Podcast"),
        unsavedEpisode: try Create.unsavedEpisode(
          guid: "with-embedding",
          title: "Has Embedding"
        )
      )
    )

    try await recommendationRepo.upsertEmbeddings([
      UnsavedEpisodeEmbedding(
        episodeId: podcastEpisode.id,
        vector: UnsavedEpisodeEmbedding.vectorData(from: [1.0, 0.0, 0.0]),
        sourceHash: "test-hash",
        embeddingRevision: 1,
        dimension: 3,
        verificationDate: Date()
      )
    ])

    let listable = try await fetchListablePodcastEpisode(podcastEpisode.id)

    #expect(listable.hasEmbedding == true)
  }
}
