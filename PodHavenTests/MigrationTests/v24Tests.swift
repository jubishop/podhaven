// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v24 migration tests", .container)
class V24MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v24 migration adds notifyNewEpisodes column to podcast table with default value")
  func testV24Migration() async throws {
    // Apply migrations up to v23
    try migrator.migrate(appDB.db, upTo: "v23")

    // Insert test podcast before migration
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

    // Verify notifyNewEpisodes column doesn't exist yet
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        !colNames.contains("notifyNewEpisodes"),
        "notifyNewEpisodes column should not exist before v24"
      )
    }

    // Apply v24 migration
    try migrator.migrate(appDB.db, upTo: "v24")

    // Verify notifyNewEpisodes column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("notifyNewEpisodes"),
        "notifyNewEpisodes column should exist after v24"
      )

      // Verify it's a BOOLEAN type
      let notifyNewEpisodesCol = cols.first { $0["name"] as? String == "notifyNewEpisodes" }
      #expect(notifyNewEpisodesCol != nil)
      let type = notifyNewEpisodesCol?["type"] as? String
      #expect(type == "BOOLEAN", "notifyNewEpisodes should be BOOLEAN type")

      // Verify it's NOT NULL
      let notNull = notifyNewEpisodesCol?["notnull"] as? Int64
      #expect(notNull == 1, "notifyNewEpisodes should be NOT NULL")

      // Verify default value
      let dfltValue = notifyNewEpisodesCol?["dflt_value"] as? String
      #expect(dfltValue == "0", "notifyNewEpisodes should have default value of false (0)")
    }

    // Test that existing podcast has false as default value after migration
    try await appDB.db.read { db in
      if let notifyNewEpisodes = try Bool.fetchOne(
        db,
        sql: "SELECT notifyNewEpisodes FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      ) {
        #expect(
          notifyNewEpisodes == false,
          "Existing podcast should have false as notifyNewEpisodes after migration"
        )
      }
    }

    // Test inserting podcasts with different notifyNewEpisodes values
    try await appDB.db.write { db in
      // Test true value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, notifyNewEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-true.xml",
          "Podcast True",
          "https://example.com/image-true.jpg",
          "Test True",
          true,
        ]
      )

      // Test false value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, notifyNewEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-false.xml",
          "Podcast False",
          "https://example.com/image-false.jpg",
          "Test False",
          false,
        ]
      )

      // Test default value (should be false)
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-default.xml",
          "Podcast Default",
          "https://example.com/image-default.jpg",
          "Test Default",
        ]
      )
    }

    // Verify all values were inserted correctly
    let trueCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE notifyNewEpisodes = ?",
        arguments: [true]
      )
    }
    #expect(trueCount == 1, "Should have 1 podcast with notifyNewEpisodes = true")

    let falseCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE notifyNewEpisodes = ?",
        arguments: [false]
      )
    }
    #expect(falseCount == 3, "Should have 3 podcasts with notifyNewEpisodes = false")

    // Test that NULL value is rejected (NOT NULL constraint)
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, notifyNewEpisodes)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-null.xml",
            "Podcast NULL",
            "https://example.com/image-null.jpg",
            "Test NULL",
            nil,
          ]
        )
      }
    }

    // Test updating to valid values works
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET notifyNewEpisodes = ? WHERE id = ?",
        arguments: [true, testPodcastID]
      )
    }

    let updatedValue = try await appDB.db.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT notifyNewEpisodes FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      )
    }
    #expect(
      updatedValue == true,
      "Podcast should have updated notifyNewEpisodes of true"
    )
  }
}
