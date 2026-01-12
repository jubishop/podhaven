// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v19 migration tests", .container)
class V19MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v19 migration renames completionDate to finishDate in episode table")
  func testV19Migration() async throws {
    // Apply migrations up to v18
    try migrator.migrate(appDB.db, upTo: "v18")

    // Insert test data before migration
    let testPodcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml",
          "Test Podcast",
          "https://example.com/image.jpg",
          "Test Description",
        ]
      )
      return db.lastInsertedRowID
    }

    let testFinishDate = Date()
    let testEpisodeID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, completionDate
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid",
          "https://example.com/episode.mp3",
          "Test Episode",
          Date(),
          testFinishDate,
        ]
      )
      return db.lastInsertedRowID
    }

    // Verify completionDate column exists before migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("completionDate"),
        "completionDate column should exist before v19"
      )
      #expect(
        !colNames.contains("finishDate"),
        "finishDate column should not exist before v19"
      )
    }

    // Verify data is accessible via old column name
    let preCompletionDate = try await appDB.db.read { db in
      try Date.fetchOne(
        db,
        sql: "SELECT completionDate FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      )
    }
    #expect(
      preCompletionDate?.approximatelyEquals(testFinishDate) == true,
      "Should be able to read completionDate before migration"
    )

    // Apply v19 migration
    try migrator.migrate(appDB.db, upTo: "v19")

    // Verify finishDate column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("finishDate"),
        "finishDate column should exist after v19"
      )
      #expect(
        !colNames.contains("completionDate"),
        "completionDate column should not exist after v19"
      )
    }

    // Verify data was preserved in renamed column
    let postFinishDate = try await appDB.db.read { db in
      try Date.fetchOne(
        db,
        sql: "SELECT finishDate FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      )
    }
    #expect(
      postFinishDate?.approximatelyEquals(testFinishDate) == true,
      "Data should be preserved after column rename"
    )

    // Verify we can't access old column name after migration
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.read { db in
        try Date.fetchOne(
          db,
          sql: "SELECT completionDate FROM episode WHERE id = ?",
          arguments: [testEpisodeID]
        )
      }
    }

    // Test inserting new episode with finishDate
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, finishDate
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid-2",
          "https://example.com/episode2.mp3",
          "Test Episode 2",
          Date(),
          Date(),
        ]
      )
    }

    // Verify new episode was inserted successfully
    let episodeCount = try await appDB.db.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")
    }
    #expect(episodeCount == 2, "Should have 2 episodes after inserting new one")
  }
}
