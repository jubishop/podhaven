// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v22 migration tests", .container)
class V22MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v22 migration adds saveInCache column to episode table with default value")
  func testV22Migration() async throws {
    // Apply migrations up to v21
    try migrator.migrate(appDB.db, upTo: "v21")

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

    let testEpisodeID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate
          ) VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid",
          "https://example.com/episode.mp3",
          "Test Episode",
          Date(),
        ]
      )
      return db.lastInsertedRowID
    }

    // Verify saveInCache column doesn't exist yet
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        !colNames.contains("saveInCache"),
        "saveInCache column should not exist before v22"
      )
    }

    // Apply v22 migration
    try migrator.migrate(appDB.db, upTo: "v22")

    // Verify saveInCache column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("saveInCache"),
        "saveInCache column should exist after v22"
      )

      // Verify it's a BOOLEAN type
      let saveInCacheCol = cols.first { $0["name"] as? String == "saveInCache" }
      #expect(saveInCacheCol != nil)
      let type = saveInCacheCol?["type"] as? String
      #expect(type == "BOOLEAN", "saveInCache should be BOOLEAN type")

      // Verify it's NOT NULL
      let notNull = saveInCacheCol?["notnull"] as? Int64
      #expect(notNull == 1, "saveInCache should be NOT NULL")

      // Verify default value
      let dfltValue = saveInCacheCol?["dflt_value"] as? String
      #expect(dfltValue == "0", "saveInCache should have default value of false (0)")
    }

    // Test that existing episode has false as default value after migration
    try await appDB.db.read { db in
      if let saveInCache = try Bool.fetchOne(
        db,
        sql: "SELECT saveInCache FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      ) {
        #expect(
          saveInCache == false,
          "Existing episode should have false as saveInCache after migration"
        )
      }
    }

    // Test inserting episodes with different saveInCache values
    try await appDB.db.write { db in
      // Test true value
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, saveInCache
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid-true",
          "https://example.com/episode-true.mp3",
          "Episode True",
          Date(),
          true,
        ]
      )

      // Test false value
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, saveInCache
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid-false",
          "https://example.com/episode-false.mp3",
          "Episode False",
          Date(),
          false,
        ]
      )

      // Test default value (should be false)
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate
          ) VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid-default",
          "https://example.com/episode-default.mp3",
          "Episode Default",
          Date(),
        ]
      )
    }

    // Verify all values were inserted correctly
    let trueCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE saveInCache = ?",
        arguments: [true]
      )
    }
    #expect(trueCount == 1, "Should have 1 episode with saveInCache = true")

    let falseCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE saveInCache = ?",
        arguments: [false]
      )
    }
    #expect(falseCount == 3, "Should have 3 episodes with saveInCache = false")

    // Test that NULL value is rejected (NOT NULL constraint)
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate, saveInCache
            ) VALUES (?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            testPodcastID,
            "test-guid-null",
            "https://example.com/episode-null.mp3",
            "Episode NULL",
            Date(),
            nil,
          ]
        )
      }
    }

    // Test updating to valid values works
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET saveInCache = ? WHERE id = ?",
        arguments: [true, testEpisodeID]
      )
    }

    let updatedValue = try await appDB.db.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT saveInCache FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      )
    }
    #expect(
      updatedValue == true,
      "Episode should have updated saveInCache of true"
    )
  }
}
