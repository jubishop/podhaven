// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v34 migration tests", .container)
class V34MigrationTests {
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

  private static func insertEpisode(
    _ db: Database,
    podcastID: Int64,
    rating: String? = nil,
    ratingDate: String? = nil
  ) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, rating, ratingDate)
        VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, ?, ?)
        """,
      arguments: [
        podcastID, "ep-\(UUID())", "https://example.com/ep-\(UUID()).mp3", "Test Episode",
        rating, ratingDate,
      ]
    )
    return db.lastInsertedRowID
  }

  // MARK: - Tests

  @Test("adds rating and ratingDate columns to episode table")
  func ratingColumnsExist() async throws {
    try migrator.migrate(appDB.db, upTo: "v34")

    try await appDB.db.read { db in
      let columns = try db.columns(in: "episode").map(\.name)
      #expect(columns.contains("rating"))
      #expect(columns.contains("ratingDate"))
    }
  }

  @Test("rating column accepts valid values")
  func ratingColumnAcceptsValidValues() async throws {
    try migrator.migrate(appDB.db, upTo: "v34")

    try await appDB.db.write { db in
      let podcastID = try V34MigrationTests.insertPodcast(db)
      _ = try V34MigrationTests.insertEpisode(db, podcastID: podcastID, rating: "loved")
      _ = try V34MigrationTests.insertEpisode(db, podcastID: podcastID, rating: "liked")
      _ = try V34MigrationTests.insertEpisode(db, podcastID: podcastID, rating: "disliked")
      _ = try V34MigrationTests.insertEpisode(db, podcastID: podcastID, rating: nil)
    }

    try await appDB.db.read { db in
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")
      #expect(count == 4)
    }
  }

  @Test("rating column rejects invalid values")
  func ratingColumnRejectsInvalid() async throws {
    try migrator.migrate(appDB.db, upTo: "v34")

    do {
      try await appDB.db.write { db in
        let podcastID = try V34MigrationTests.insertPodcast(db)
        _ = try V34MigrationTests.insertEpisode(db, podcastID: podcastID, rating: "invalid")
      }
      Issue.record("Expected CHECK constraint to reject invalid rating")
    } catch {
      // Expected: CHECK constraint violation
    }
  }
}
