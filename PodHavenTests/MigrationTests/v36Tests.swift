// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v36 migration tests", .container)
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

  // MARK: - Column Tests

  @Test("adds contentUpdatedAt column to episode table")
  func episodeContentUpdatedAtExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let columns = try db.columns(in: "episode").map(\.name)
      #expect(columns.contains("contentUpdatedAt"))
    }
  }

  @Test("adds contentUpdatedAt column to podcast table")
  func podcastContentUpdatedAtExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let columns = try db.columns(in: "podcast").map(\.name)
      #expect(columns.contains("contentUpdatedAt"))
    }
  }

  @Test("contentUpdatedAt defaults to CURRENT_TIMESTAMP for new episodes")
  func episodeContentUpdatedAtDefaults() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.write { db in
      let podcastID = try V36MigrationTests.insertPodcast(db)
      let episodeID = try V36MigrationTests.insertEpisode(db, podcastID: podcastID)

      let value = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [episodeID]
      )
      #expect(value != nil)
    }
  }

  @Test("contentUpdatedAt defaults to CURRENT_TIMESTAMP for new podcasts")
  func podcastContentUpdatedAtDefaults() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.write { db in
      let podcastID = try V36MigrationTests.insertPodcast(db)

      let value = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [podcastID]
      )
      #expect(value != nil)
    }
  }

  // MARK: - Trigger Tests

  @Test("episode_content_updated trigger exists")
  func episodeTriggerExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let triggers = try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'trigger' AND tbl_name = 'episode'
          """
      )
      #expect(triggers.contains("episode_content_updated"))
    }
  }

  @Test("podcast_content_updated trigger exists")
  func podcastTriggerExists() async throws {
    try migrator.migrate(appDB.db, upTo: "v36")

    try await appDB.db.read { db in
      let triggers = try String.fetchAll(
        db,
        sql: """
          SELECT name FROM sqlite_master
          WHERE type = 'trigger' AND tbl_name = 'podcast'
          """
      )
      #expect(triggers.contains("podcast_content_updated"))
    }
  }
}
