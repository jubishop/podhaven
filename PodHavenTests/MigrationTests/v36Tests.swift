// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v36 migration tests (embedding cache tables)", .container)
class V36MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Helpers

  private static func insertPodcast(_ db: Database) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO podcast (feedURL, title, image, description)
        VALUES ('https://example.com/feed.xml', 'Test', 'img', 'desc')
        """
    )
    return db.lastInsertedRowID
  }

  private static func insertEpisode(_ db: Database, podcastID: Int64) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        """,
      arguments: [
        podcastID, "ep-\(UUID())", "https://example.com/ep-\(UUID()).mp3", "Test Episode",
      ]
    )
    return db.lastInsertedRowID
  }

  // MARK: - Tests

  @Test("creates episodeEmbedding table with correct columns")
  func episodeEmbeddingTableExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let columns = try db.columns(in: "episodeEmbedding").map(\.name)
      #expect(columns.contains("episodeId"))
      #expect(columns.contains("vector"))
      #expect(columns.contains("sourceHash"))
      #expect(columns.contains("embeddingRevision"))
      #expect(columns.contains("dimension"))
      #expect(columns.contains("creationDate"))
    }
  }

  @Test("creates podcastEmbedding table with correct columns")
  func podcastEmbeddingTableExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let columns = try db.columns(in: "podcastEmbedding").map(\.name)
      #expect(columns.contains("podcastId"))
      #expect(columns.contains("vector"))
      #expect(columns.contains("sourceHash"))
      #expect(columns.contains("embeddingRevision"))
      #expect(columns.contains("dimension"))
      #expect(columns.contains("creationDate"))
    }
  }

  @Test("episodeEmbedding cascades on episode delete")
  func episodeEmbeddingCascade() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.write { db in
      let podcastID = try V36MigrationTests.insertPodcast(db)
      let episodeID = try V36MigrationTests.insertEpisode(db, podcastID: podcastID)

      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (episodeId, vector, sourceHash, embeddingRevision, dimension)
          VALUES (?, X'00000000', 'test', 1, 3)
          """,
        arguments: [episodeID]
      )

      let beforeDelete = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [episodeID]
      )
      #expect(beforeDelete == 1)

      try db.execute(
        sql: "DELETE FROM episode WHERE id = ?",
        arguments: [episodeID]
      )

      let afterDelete = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [episodeID]
      )
      #expect(afterDelete == 0)
    }
  }

  @Test("podcastEmbedding cascades on podcast delete")
  func podcastEmbeddingCascade() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.write { db in
      let podcastID = try V36MigrationTests.insertPodcast(db)

      try db.execute(
        sql: """
          INSERT INTO podcastEmbedding (podcastId, vector, sourceHash, embeddingRevision, dimension)
          VALUES (?, X'00000000', 'test', 1, 3)
          """,
        arguments: [podcastID]
      )

      let beforeDelete = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcastEmbedding WHERE podcastId = ?",
        arguments: [podcastID]
      )
      #expect(beforeDelete == 1)

      try db.execute(
        sql: "DELETE FROM podcast WHERE id = ?",
        arguments: [podcastID]
      )

      let afterDelete = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcastEmbedding WHERE podcastId = ?",
        arguments: [podcastID]
      )
      #expect(afterDelete == 0)
    }
  }
}
