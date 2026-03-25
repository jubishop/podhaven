// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v35 migration tests (embedding cache tables)", .container)
class V35MigrationTests {
  @DynamicInjected(\.appDB) private var appDB

  @Test("v35 creates episodeEmbedding table with correct columns")
  func episodeEmbeddingTableExists() async throws {
    let columns = try await appDB.db.read { db in
      try db.columns(in: "episodeEmbedding").map(\.name)
    }
    #expect(columns.contains("episodeId"))
    #expect(columns.contains("vector"))
    #expect(columns.contains("sourceHash"))
    #expect(columns.contains("embeddingRevision"))
    #expect(columns.contains("dimension"))
    #expect(columns.contains("creationDate"))
  }

  @Test("v35 creates podcastEmbedding table with correct columns")
  func podcastEmbeddingTableExists() async throws {
    let columns = try await appDB.db.read { db in
      try db.columns(in: "podcastEmbedding").map(\.name)
    }
    #expect(columns.contains("podcastId"))
    #expect(columns.contains("vector"))
    #expect(columns.contains("sourceHash"))
    #expect(columns.contains("embeddingRevision"))
    #expect(columns.contains("dimension"))
    #expect(columns.contains("creationDate"))
  }

  @Test("episodeEmbedding cascades on episode delete")
  func episodeEmbeddingCascade() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let podcastEpisodes = try await Container.shared.repo()
      .upsertPodcastEpisodes([
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
      ])
    let episodeID = podcastEpisodes.first!.episode.id
    let podcastID = podcastEpisodes.first!.podcast.id

    let testVector: [Float] = [1.0, 0.0, 0.0]
    let unsaved = UnsavedEpisodeEmbedding(
      episodeId: episodeID,
      vector: UnsavedEpisodeEmbedding.vectorData(from: testVector),
      sourceHash: "test",
      embeddingRevision: 1,
      dimension: 3
    )
    try await Container.shared.repo().upsertEmbedding(unsaved)

    let beforeDelete = try await Container.shared.repo().embedding(for: episodeID)
    #expect(beforeDelete != nil)

    _ = try await Container.shared.repo().deletePodcast(podcastID)

    let afterDelete = try await Container.shared.repo().embedding(for: episodeID)
    #expect(afterDelete == nil)
  }
}
