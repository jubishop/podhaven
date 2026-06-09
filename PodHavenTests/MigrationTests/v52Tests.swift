// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v52 migration tests", .container)
class V52MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed at v51 with one podcast, one episode, and one embedding row so the
  // new covering index has data beneath it when v52 runs.
  private func populateAtV51() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            600, 'https://example.com/v52.xml', 'V52 Podcast',
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
            610, 600, 'guid-1', 'https://example.com/ep1.mp3',
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
            620, 610, x'00112233', 'hash-1', 3, 512,
            '2024-03-01 00:00:00', '2024-03-01 00:00:00'
          )
          """
      )
    }
  }

  // MARK: - Index Changes

  @Test("v52 adds the covering embedding-needs index")
  func addsCoveringEmbeddingIndex() async throws {
    try await populateAtV51()

    let indexName = "episodeEmbedding_on_episodeId_embeddingRevision_verificationDate"
    let before = try await indexNames(on: "episodeEmbedding")
    #expect(!before.contains(indexName))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v52")

    let after = try await indexNames(on: "episodeEmbedding")
    #expect(after.contains(indexName))

    let indexedColumns = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "PRAGMA index_info('\(indexName)')")
        .map { $0["name"] as String }
    }
    #expect(indexedColumns == ["episodeId", "embeddingRevision", "verificationDate"])
  }

  // MARK: - Data Preservation

  @Test("v52 leaves existing embedding rows intact")
  func preservesEmbeddings() async throws {
    try await populateAtV51()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v52")

    try await appDB.unsafeTestDB.read { db in
      let row = try #require(
        try Row.fetchOne(db, sql: "SELECT * FROM episodeEmbedding WHERE id = 620")
      )
      #expect(row["episodeId"] as Int == 610)
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
