// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v53 migration tests", .container)
class V53MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed at v52 with one podcast, one episode, and one embedding row so the
  // new covering index has data beneath it when v53 runs.
  private func populateAtV52() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v52")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            700, 'https://example.com/v53.xml', 'V53 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading
          ) VALUES (
            710, 700, 'guid-1', 'https://example.com/ep1.mp3',
            'Embedded', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 0
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            id, episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate, verificationDate
          ) VALUES (
            720, 710, x'00112233', 'hash-1', 3, 512,
            '2024-03-01 00:00:00', '2024-03-01 00:00:00'
          )
          """
      )
    }
  }

  // MARK: - Index Changes

  @Test("v53 adds the covering embedding-needs index")
  func addsCoveringEmbeddingIndex() async throws {
    try await populateAtV52()

    let indexName = "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate"
    let before = try await indexNames(on: "episodeEmbedding")
    #expect(!before.contains(indexName))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v53")

    let after = try await indexNames(on: "episodeEmbedding")
    #expect(after.contains(indexName))

    let indexedColumns = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "PRAGMA index_info('\(indexName)')")
        .map { $0["name"] as String }
    }
    #expect(indexedColumns == ["episodeId", "embeddingRevision", "verificationDate"])
  }

  // MARK: - Data Preservation

  @Test("v53 leaves existing embedding rows intact")
  func preservesEmbeddings() async throws {
    try await populateAtV52()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v53")

    try await appDB.unsafeTestDB.read { db in
      let row = try #require(
        try Row.fetchOne(db, sql: "SELECT * FROM episodeEmbedding WHERE id = 720")
      )
      #expect(row["episodeId"] as Int == 710)
      #expect(row["embeddingRevision"] as Int == 3)
      #expect(row["sourceHash"] as String == "hash-1")
    }
  }

  private func indexNames(on table: String) async throws -> Set<String> {
    try await appDB.unsafeTestDB.read { db in
      Set(
        try Row.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
          arguments: [table]
        )
        .map { $0["name"] as String }
      )
    }
  }
}
