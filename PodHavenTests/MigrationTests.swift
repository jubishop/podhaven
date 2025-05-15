// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Migration tests", .container)
class MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("migrating to v2, assigning completion dates")
  func testV2Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v1")

    // Insert test data in v1 schema (with 'completed' column)
    let now = Date()
    let yesterday = 24.hoursAgo

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create two episodes - one completed, one not completed
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, completed, currentTime)
            VALUES (?, 'completedGUID', 'https://example.com/ep1.mp3', 'Completed Episode', ?, 1, 0)
          """,
        arguments: [podcastId, yesterday]
      )

      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, completed, currentTime)
            VALUES (?, 'uncompletedGUID', 'https://example.com/ep2.mp3', 'Incomplete Episode', ?, 0, 0)
          """,
        arguments: [podcastId, now]
      )
    }

    // Migrate to v2
    try migrator.migrate(appDB.db, upTo: "v2")

    // Verify the migration results
    try await appDB.db.read { db in
      // Check that the completed episode has completionDate set to pubDate
      let completedRow = try Row.fetchOne(
        db,
        sql: """
            SELECT * FROM episode WHERE guid = 'completedGUID'
          """
      )!

      let completionDate = completedRow[Column("completionDate")] as Date?
      let pubDate = completedRow[Column("pubDate")] as Date
      #expect(completionDate == pubDate)

      // Check that the incomplete episode has nil completionDate
      let incompleteRow = try Row.fetchOne(
        db,
        sql: """
            SELECT * FROM episode WHERE guid = 'uncompletedGUID'
          """
      )!
      #expect(incompleteRow[Column("completionDate")] as Date? == nil)

      // Verify the completed column was removed
      let columns = try db.columns(in: "episode").map { $0.name }
      #expect(columns.contains("completed") == false)
      #expect(columns.contains("completionDate") == true)
    }
  }
}
